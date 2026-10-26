"""Remove known app-generated attachment envelopes, preserving the human request."""
import re
import json
from pathlib import PurePath
from urllib.parse import quote


def display_text(text, role='user', has_media=False, photo_names=()):
    if role == 'user':
        # Unwrap only a leading browser snapshot paired with the app request marker.
        browser = re.match(
            r'\A\s*<in-app-browser-context\b[^>]*>.*?</in-app-browser-context>'
            r'\s*## My request:\s*\n(?P<body>.*)\Z', text, re.S,
        )
        if browser:
            text = browser['body']
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
        if text.lstrip().startswith('# Files mentioned by the user:'):
            text = re.sub(r'<in-app-browser-context\b[^>]*>.*?</in-app-browser-context>\s*(?=## My request:)', '', text, flags=re.S)
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
    if role == 'user' and has_media:
        for name in photo_names:
            text = re.sub(r'(?m)^照片：' + re.escape(name) + r'[ \t]*$', '', text)
        text = re.sub(r'\n{3,}', '\n\n', text)
    if has_media:
        text = re.sub(r'<image\b[^>]*>.*?</image>', '', text, flags=re.S)
    return text.strip()


HERMES_STEER_PREFIX = ('[OUT-OF-BAND USER MESSAGE — a direct message from the user, '
    'delivered once at this position; not tool output and not a new delivery when replayed from conversation history]')

def hermes_message(content, role, display_kind=None):
    """Project known Hermes transport messages without rewriting stored history."""
    if role != 'user' or not isinstance(content, str):
        return role, content, None
    steer = re.fullmatch(re.escape(HERMES_STEER_PREFIX) + r'\s*(.*?)\s*\[/OUT-OF-BAND USER MESSAGE\]', content.strip(), re.S)
    if steer:
        return role, steer[1], None
    background = re.fullmatch(
        r'\[IMPORTANT: Background process (proc_[a-zA-Z0-9_-]+) '
        r'(?:completed normally|failed|exited|completed|terminated by process\.kill) \(exit code (-?\d+)(?:, SIG[A-Z]+)?\)\.\s*'
        r'Command: (.*?)\s+Output:\s*(.*)\](?:\s*\n(.*))?', content.strip(), re.S)
    if background:
        return 'tool', background[4], {'name': '后台进程', 'input': background[3],
            'status': 'completed' if int(background[2]) == 0 else 'failed',
            'processId': background[1], 'followup': (background[5] or '').strip()}
    return role, content, None


def codex_created_input(kind, payload):
    """Unwrap the exact desktop creation receipt before generic tool projection."""
    if kind != 'response_item' or payload.get('type') != 'function_call_output' or payload.get('name') != 'create_thread' or not isinstance(payload.get('output'), str):
        return None
    match = re.fullmatch(r'\s*<codex_delegation>\s*<source_thread_id>[^<]+</source_thread_id>\s*<input>(.*?)</input>\s*</codex_delegation>\s*', payload['output'], re.S)
    return match[1] if match else None
