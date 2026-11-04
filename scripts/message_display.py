"""Remove known app-generated attachment envelopes, preserving the human request."""
import re
import json
from pathlib import PurePath
from urllib.parse import quote


def visible_user_media(text, media):
    """Keep original attachments, hide only our own video sampling frames."""
    paths = re.findall(r'<image\b[^>]*\bpath="([^"]+)"[^>]*>\s*</image>', text)
    if len(paths) != len(media):
        return text, media
    hidden = set()
    for i, path in enumerate(paths):
        match = re.fullmatch(r'(.*/uploads/[a-f0-9-]{36})/media/frame-\d+\.jpg', path)
        if match and re.search(r'视频附件：\[[^\]]+\]\(' + re.escape(quote(match[1] + '/content', safe='/')) + r'\)', text):
            hidden.add(i)
    if hidden:
        text = re.sub(r'(?m)^以下是视频画面的均匀抽样，不含音频。[^\n]*\n?', '', text)
        text = re.sub(r'(?m)^视频画面 \d+ · \d+(?:\.\d+)? 秒\s*$', '', text)
        # The image tags are removed by display_text; retain real photo parts.
        media = [ref for i, ref in enumerate(media) if i not in hidden]
        text = re.sub(r'<image\b[^>]*>.*?</image>', '', text, flags=re.S)
    return text, media


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
                if PurePath(path).suffix.lower() in {'.pdf','.docx','.doc','.md','.txt','.csv','.xlsx','.pptx','.zip','.mp4','.mov','.m4v','.webm'} and path not in text:
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

def hermes_internal_message(content, display_kind=None, compressed=False):
    """Hide native transport summaries; never infer from ordinary prose."""
    return bool(compressed or display_kind in ('hidden', 'internal_notification') or
        (isinstance(content, str) and content.lstrip().startswith('[CONTEXT COMPACTION — REFERENCE ONLY]')))


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


def codex_generated_image(kind, payload, home, thread_id):
    """Only completed native image generation records from this thread."""
    from pathlib import Path
    if kind != 'event_msg' or payload.get('type') != 'item_completed':
        return None
    item = payload.get('item') or {}
    if item.get('type') != 'Extension' or item.get('kind') != 'image_gen.generation' or item.get('status') != 'completed':
        return None
    saved = item.get('savedPath')
    if not isinstance(saved, str):
        return None
    root = (Path(home) / '.codex/generated_images' / thread_id).resolve()
    path = Path(saved).resolve()
    if not path.is_relative_to(root) or path.suffix.lower() not in {'.png', '.jpg', '.jpeg', '.webp'}:
        return None
    return str(path)


def group_generated_images(events):
    groups = {}
    for event in events:
        if str(event.get('id', '')).startswith('generated:') and event.get('turnId'):
            groups.setdefault(event['turnId'], []).append(event)
    removed = set()
    for turn, images in groups.items():
        candidates = [e for e in events if e.get('role') == 'assistant' and e.get('turnId') == turn and e not in images and e.get('text')]
        target = candidates[-1] if candidates else images[0]
        target['media'] = list(dict.fromkeys((target.get('media') or []) + [ref for image in images for ref in image.get('media', [])]))
        removed.update(id(e) for e in images if e is not target)
    return [e for e in events if id(e) not in removed]
