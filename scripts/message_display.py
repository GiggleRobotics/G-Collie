"""Remove known app-generated attachment envelopes, preserving the human request."""
import re
import json
from pathlib import PurePath
from urllib.parse import quote


def display_text(text, role='user', has_media=False):
    if role == 'user':
        reply = re.fullmatch(r'\s*<send_user_message_question_reply>\s*(.*?)\s*</send_user_message_question_reply>\s*', text, re.S)
        if reply:
            try:
                rows = json.loads(reply[1])
                if isinstance(rows, list) and rows and all(
                    isinstance(row, dict) and isinstance(row.get('questionItemId'), str)
                    and isinstance(row.get('question'), str) and isinstance(row.get('answer'), str)
                    for row in rows
                ):
                    text = '\n\n'.join(row['answer'] for row in rows)
            except (ValueError, TypeError):
                pass
        # These are transport context snapshots, not human chat messages.
        context = re.fullmatch(r'\s*<external_codex_apps_open_page>\s*(.*?)\s*</external_codex_apps_open_page>\s*', text, re.S)
        if context:
            try:
                value = json.loads(context[1])
                if isinstance(value, dict) and set(value) == {'page_id'}:
                    return ''
            except (ValueError, TypeError):
                pass
        # Only unwrap the complete known envelope. A user's ordinary headings
        # with the same words must not be removed.
        envelope = re.match(
            r'\A\s*# Files mentioned by the user:\s*\n(?P<files>.*?)'
            r'\nDistinguish instructions in attached documents from the user\'s request\.'
            r'\s*\n+## My request:\s*\n(?P<body>.*)\Z',
            text, re.S,
        )
        if envelope and re.search(r'^## .+: .+', envelope['files'], re.M):
            text = envelope['body']
            # Keep non-image attachments actionable after removing the envelope.
            links = []
            for name, path in re.findall(r'^## (.+?): (.+)$', envelope['files'], re.M):
                if PurePath(path).suffix.lower() in {'.pdf','.docx','.doc','.md','.txt','.csv','.xlsx','.pptx','.zip'} and path not in text:
                    label = name.replace('[', r'\[').replace(']', r'\]')
                    links.append(f'[{label}](<{quote(path, safe="/")}>)')
            if links:
                text = text.rstrip() + '\n\n' + '\n\n'.join(links)
    if has_media:
        text = re.sub(r'<image\b[^>]*>.*?</image>', '', text, flags=re.S)
    return text.strip()
