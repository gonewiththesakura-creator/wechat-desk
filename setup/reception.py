"""Acknowledge incoming individual chats using only the isolated WeChat window."""

import collections
import datetime
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import time
from pathlib import Path
import pyatspi as atspi
from PIL import ImageGrab

REPLY = "收到你的消息了。"
CONTROL = Path("/mnt/d/WeChatDesk/control")
STATUS = CONTROL / "status.json"
EXCLUDED = {
    "文件传输助手",
    "微信支付",
    "服务通知",
    "订阅号消息",
    "公众号",
    "微信团队",
    "File Transfer",
    "File Transfer Assistant",
    "Weixin Pay",
    "Official Accounts",
}
CLOCK = re.compile(r"\d{1,2}:\d{2}")
UNREAD = re.compile(r"\[\d+条\]")


class Skip(ValueError):
    pass


def children(node):
    return [child for child in node if child is not None]


def walk(root, stop_lists=False):
    stack = [root]
    while stack:
        node = stack.pop()
        yield node
        if not (stop_lists and node.getRoleName() == "list"):
            stack.extend(reversed(children(node)))


def rect(node):
    e = node.queryComponent().getExtents(atspi.DESKTOP_COORDS)
    return e.x, e.y, e.width, e.height


def ui(frame):
    return [n for n in walk(frame, True) if n.getState().contains(atspi.STATE_SHOWING)]


def pick(nodes, roles, names):
    for n in nodes:
        if n.getRoleName() in roles and n.name.strip() in names:
            return n
    return None


def command(*args):
    return subprocess.check_output(
        ["xdotool", *map(str, args)], text=True, timeout=3, stderr=subprocess.DEVNULL
    ).strip()


def frame_now():
    apps = [
        app
        for app in children(atspi.Registry.getDesktop(0))
        if app.name.lower() in {"wechat", "weixin", "微信"}
    ]
    if len(apps) == 1:
        visible = [
            n for n in children(apps[0]) if n.getState().contains(atspi.STATE_SHOWING)
        ]
        frames = [n for n in visible if n.getRoleName() == "frame"]
        if len(frames) == 1 and len(visible) == 1:
            return frames[0]
    raise ValueError("等待微信主界面或弹窗关闭")


def ensure_target():
    if os.environ.get("DISPLAY") != ":83" or (CONTROL / "paused").exists():
        raise ValueError("接待已暂停")
    win = command("getactivewindow")
    prop = subprocess.check_output(
        ["xprop", "-id", win, "WM_CLASS"], text=True, timeout=3
    )
    if not (set(re.findall(r'"([^"]+)"', prop.lower())) & {"wechat", "weixin"}):
        raise ValueError("等待独立桌面的微信窗口")
    return win


def coordinates():
    win = ensure_target()
    info = subprocess.check_output(["xwininfo", "-id", win], text=True, timeout=2)

    def number(key):
        return int(re.search(key + r":\s*(-?\d+)", info).group(1))

    fx, fy, fw, fh = rect(frame_now())
    ox, oy = number("Absolute upper-left X"), number("Absolute upper-left Y")
    sx, sy = number("Width") / fw, number("Height") / fh
    if not (0.7 < sx < 2.5 and abs(sx - sy) < 0.02):
        raise ValueError("等待微信窗口布局稳定")
    return lambda x, y: (round(ox + (x - fx) * sx), round(oy + (y - fy) * sy))


def click(node):
    x, y, w, h = rect(node)
    if x < 0 or y < 0 or min(w, h) < 2:
        raise ValueError("控件暂时不可见")
    command("mousemove", *coordinates()(x + w / 2, y + h / 2), "click", 1)


def sessions(nodes):
    box = pick(nodes, {"list"}, {"会话", "Chats", "Conversations"})
    if box is None:
        raise ValueError("等待微信会话列表")
    rows = {}
    for node in children(box):
        lines = [v.strip() for v in node.name.splitlines()]
        if node.getRoleName() != "list item" or len(lines) < 3 or not lines[0]:
            continue
        name = lines[0]
        end = next(
            (i for i in range(len(lines) - 1, 0, -1) if CLOCK.fullmatch(lines[i])), None
        )
        if end is None:
            continue
        parts = lines[1:end]
        unread = 0
        while parts:
            if parts[0] in {"已置顶", "置顶"}:
                parts.pop(0)
            elif UNREAD.fullmatch(parts[0]):
                unread = int(parts.pop(0)[1:-2])
            else:
                break
        preview = "\n".join(parts).strip()
        if preview:
            rows[name] = None if name in rows else (node, preview, lines[end], unread)
    return rows


def chat_view(name):
    nodes = ui(frame_now())
    hist = pick(nodes, {"list"}, {"消息", "Messages"})
    if hist is None:
        raise ValueError("等待聊天记录区")
    x, y, w, h = rect(hist)
    titles = [
        n
        for n in nodes
        if n.getRoleName() == "label"
        and x <= rect(n)[0] < x + w / 2
        and y - 48 <= rect(n)[1] < y
    ]
    if not any(n.name.strip() == name for n in titles):
        raise ValueError("等待确认会话名称")
    if any(re.search(r"[（(]\d+[）)]$", n.name) for n in titles):
        raise Skip("跳过群聊")
    return nodes, hist


def confirm_private(name):
    nodes, hist = chat_view(name)
    info = pick(nodes, {"button"}, {"聊天信息"})
    if info is None:
        raise Skip("跳过特殊会话")
    click(info)
    time.sleep(0.25)
    try:
        ns, h = chat_view(name)
        if pick(ns, {"list"}, {"聊天成员"}):
            raise Skip("跳过群聊")
        if not (
            pick(ns, {"button"}, {"添加"})
            and pick(ns, {"check box"}, {"消息免打扰"})
            and pick(ns, {"button"}, {"清空聊天记录"})
        ):
            raise ValueError("未确认私聊信息面板")
    finally:
        x, y, w, h = rect(hist)
        command("mousemove", *coordinates()(x + w * 0.22, y - 8), "click", 1)
        time.sleep(0.2)


def latest(hist):
    items = children(hist)
    if not items:
        raise ValueError("等待消息气泡")
    last = items[-1]
    hx, hy, hw, hh = rect(hist)
    x, y, w, h = rect(last)
    if w < hw * 0.85 or h < 32 or y + 34 >= hy + hh or y < hy - 2:
        raise ValueError("最新消息暂不可见")
    p = coordinates()
    x1, y1 = p(hx, y)
    x2, y2 = p(hx + hw, y + 44)
    # Compare only the two avatar gutters. System notices have no avatar.
    im = ImageGrab.grab(bbox=(x1, y1, x2, y2), xdisplay=":83").convert("RGB")

    def pixel(dx, dy):
        xx, yy = p(hx + dx, y + dy)
        return im.getpixel((xx - x1, yy - y1))

    def avatar(right):
        occupied = 0
        for dy in (13, 19, 25, 31):
            bg = pixel(8 if not right else hw - 8, dy)
            for dx in (24, 29, 34, 39, 44, 49):
                c = pixel(hw - dx if right else dx, dy)
                occupied += max(abs(i - j) for i, j in zip(c, bg)) > 8
        return occupied

    left, right = avatar(False), avatar(True)
    side = (
        "in"
        if left >= 12 and right <= 3
        else "out"
        if right >= 12 and left <= 3
        else None
    )
    return last.name.strip(), side


def editor_for(name, preview):
    ns, h = chat_view(name)
    msg, side = latest(h)
    if side == "out":
        raise Skip("最近一条由客服发出")
    if side != "in":
        raise ValueError("等待确认消息方向")
    # WeChat represents media as a bare type in history and a bracketed type in the list.
    media = {"图片", "视频", "动画表情", "表情", "语音", "文件"}
    match = msg == preview or (
        preview.startswith("[")
        and preview.endswith("]")
        and msg in media
        and msg == preview[1:-1]
    )
    if not match:
        raise ValueError("当前气泡与消息预览不一致")
    x, y, w, hh = rect(h)
    ed = [
        n
        for n in ns
        if n.getState().contains(atspi.STATE_EDITABLE)
        and rect(n)[0] >= x
        and rect(n)[1] >= y + hh - 8
    ]
    if len(ed) != 1:
        raise ValueError("等待聊天输入框")
    return ed[0]


def content(editor):
    return editor.queryText().getText(0, -1)


def send(name, preview, db, key):
    confirm_private(name)
    e = editor_for(name, preview)
    if content(e):
        raise Skip("当前聊天有草稿")
    click(e)
    e = editor_for(name, preview)
    if not e.getState().contains(atspi.STATE_FOCUSED) or content(e):
        raise ValueError("等待空白输入框")
    # The clipboard lives only inside Xvfb (x11vnc runs with -nosel).
    subprocess.run(
        ["xclip", "-selection", "clipboard", "-i"],
        input=REPLY.encode(),
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=3,
    )
    ensure_target()
    command("key", "ctrl+v")
    time.sleep(0.18)
    e = editor_for(name, preview)
    if not e.getState().contains(atspi.STATE_FOCUSED) or content(e) != REPLY:
        raise ValueError("未能核对回复草稿")
    button = pick(ui(frame_now()), {"button"}, {"发送", "Send"})
    if button is None:
        raise ValueError("未找到发送按钮")
    with db:
        db.execute("insert into sent values (?, 'uncertain')", (key,))
    click(button)
    for _ in range(6):
        time.sleep(0.25)
        _, h = chat_view(name)
        if latest(h) == (REPLY, "out") and not content(e):
            with db:
                db.execute("update sent set result='confirmed' where id=?", (key,))
            return
    raise ValueError("发送结果待核对")


def write_status(message, db):
    counts = dict(db.execute("select result,count(*) from sent group by result"))
    data = {
        "message": message,
        "checked": int(time.time()),
        "confirmed": counts.get("confirmed", 0),
        "uncertain": counts.get("uncertain", 0),
    }
    tmp = STATUS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    tmp.replace(STATUS)


def clock_recent(clock):
    now = datetime.datetime.now()
    return any(
        (now - datetime.timedelta(minutes=n)).strftime("%H:%M").lstrip("0")
        == clock.lstrip("0")
        for n in range(4)
    )


def switch_pin_view(nodes):
    button = pick(nodes, {"button"}, {"折叠置顶聊天"})
    if button:
        click(button)
        return
    box = pick(nodes, {"list"}, {"会话"})
    kids = children(box) if box else []
    if kids and not kids[0].name and 38 <= rect(kids[0])[3] <= 54:
        click(kids[0])


def run():
    if os.environ.get("DISPLAY") != ":83":
        raise SystemExit("Independent display required")
    db = sqlite3.connect(Path.home() / "wxdesk-receipts.sqlite3")
    db.execute(
        "create table if not exists sent (id text primary key,result text not null)"
    )
    previous = {}
    pending = collections.OrderedDict()
    start = time.time()
    switched = time.monotonic()
    notice = ""
    until = 0
    while True:
        try:
            ensure_target()
            ns = ui(frame_now())
            rows = sessions(ns)
            for name, row in rows.items():
                if not row or name in EXCLUDED:
                    continue
                _, preview, clock, unread = row
                signature = preview, clock, unread
                old = previous.get(name)
                previous[name] = signature
                if preview == REPLY:
                    continue
                if old == signature:
                    continue
                live = clock_recent(clock) and (
                    old is not None
                    and (old[:2] != signature[:2] or unread > old[2])
                    or old is None
                    and unread
                    and clock_recent(clock)
                    and time.time() - start > 2
                )
                if live:
                    if name in pending and pending[name][0:2] == (preview, clock):
                        continue
                    event = hashlib.sha256(
                        (
                            name
                            + "\0"
                            + preview
                            + "\0"
                            + clock
                            + "\0"
                            + str(time.time_ns())
                        ).encode()
                    ).hexdigest()
                    pending[name] = (preview, clock, event, 0)
            for name, job in list(pending.items()):
                row = rows.get(name)
                if not row:
                    continue
                preview, clock, key, attempt = job
                if (
                    row[1:3] != (preview, clock)
                    or db.execute("select 1 from sent where id=?", (key,)).fetchone()
                ):
                    pending.pop(name)
                    continue
                try:
                    try:
                        chat_view(name)
                    except Skip:
                        raise
                    except ValueError:
                        click(row[0])
                        time.sleep(0.4)
                    send(name, preview, db, key)
                    pending.pop(name)
                    notice = "已确认回复到原会话"
                except (Skip, ValueError, subprocess.SubprocessError) as exc:
                    notice = (
                        str(exc)
                        if isinstance(exc, ValueError)
                        else "微信窗口暂时不可操作"
                    )
                    if isinstance(exc, Skip) or attempt >= 2:
                        pending.pop(name)
                    else:
                        pending[name] = (preview, clock, key, attempt + 1)
                until = time.monotonic() + 7
                break
            else:
                if time.monotonic() - switched >= 9:
                    switch_pin_view(ns)
                    switched = time.monotonic()
            message = notice if time.monotonic() < until else "监控中"
        except Exception as exc:
            message = (
                str(exc)
                if isinstance(exc, ValueError)
                else "微信界面暂不可读，正在重试"
            )
            if (CONTROL / "paused").exists():
                pending.clear()
                previous.clear()
                start = time.time()
        write_status(message, db)
        time.sleep(1.1)


if __name__ == "__main__":
    run()
