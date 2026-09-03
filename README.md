# NotesMD

给 Apple 备忘录用的 Markdown 扩展。安装之后，写作界面仍然是 **备忘录**，资料仍然保存在原来的 iCloud / 本机 / IMAP 账户里。插件不另建数据库，也不要求迁移旧笔记。以后不用了，原来的笔记也不会消失；同步、协作、iPhone / iPad 体验都还在。

它借助辅助功能权限和 Apple Events，判断当前打开的是哪篇笔记、光标在哪里、选中了哪段文字，然后把工具栏和命令面板放在备忘录旁边。操作结束后，格式和文字写回原来的笔记。感觉接近浏览器扩展，只不过这次被扩展的是一个没有插件系统的 Mac 原生 App。

macOS 26 的备忘录已经能导入 / 导出 Markdown 文件。NotesMD 补的是 **边写边用 Markdown**。

---

A Markdown companion for **Apple Notes** on the Mac.

You still write in Apple Notes. Notes stay in the original iCloud / On My Mac / IMAP account. NotesMD does not create another database and does not require migrating old notes. Uninstalling it does not delete anything. Sync, collaboration, and iPhone / iPad Notes keep working because the source of truth never moved.

It behaves like a browser extension for an app that has no extension system: after you grant Accessibility and Automation, it watches which note is open, where the caret is, and what is selected, then docks a toolbar and command palette beside Notes. When a command finishes, the formatting is written back into that same note.

macOS 26 Notes can already import / export Markdown files. NotesMD is for **editing while you write**.

## What it does

The main UI is the **side toolbar** and **command palette**. NotesMD does not intercept `/` while you type.

- Side toolbar next to the Notes window: Title, Heading, lists, quote, checklist, convert, copy
- Slash commands (`⌘⇧P`) — `/title`, `/quote`, `/todo`, `/template`…
- Command palette (`⌘⇧↩`) — ↑↓ to choose, Return to run, Esc to close
- Slash menu from the toolbar `/` button (`/title`, `/quote`, `/todo`, `/template`…)
- Inline format bar only when text is selected
- Quick Open (`⌘O`), table of contents, Templates folder
- Optional as-you-type (`# ` `## ` `> ` `[] `) only if Accessibility can read the current line; otherwise it does nothing
- Copy / convert Markdown, preview

Paragraph styles go through Notes’ own Format menu (Title / Heading / Subheading / Body / Monostyled / lists / checklist / block quote), so they remain real Notes styles on every device.

## Install

Requires macOS 14+ and Swift command-line tools.

```bash
cd ~/NotesMD
make app
open dist/NotesMD.app
```

Drag `dist/NotesMD.app` to `/Applications` if you want it to launch at login.

## First launch

1. Open NotesMD from the menu bar (note icon).
2. Grant **Accessibility** when asked, or use **Permissions…**
3. Open **Notes**. macOS will ask to allow NotesMD to control Notes — choose **OK**.
4. Select a note. The toolbar should appear beside the Notes window.

NotesMD installs a background watcher so it starts when Apple Notes opens and quits when Notes quits. Turn this off from the menu bar item **Launch with Apple Notes**.

## Shortcuts (while Notes is frontmost)

| Shortcut | Action |
| --- | --- |
| `⌘⇧P` | Slash commands |
| `⌘⇧↩` | Command palette |
| `⌘⇧M` | Toggle toolbar |
| `⌘O` | Quick Open |
| Toolbar `/` | Slash commands |
| `#` `##` `>` `[]` + space | Optional, only if the current line is readable |

## How write-back works

1. **Native Format menu** for Title, Heading, lists, checklist, quote — same commands you would click yourself.
2. **Selection replace + paste** for richer Markdown (links, mixed inline styles, documents). HTML is placed on the clipboard and pasted into the current note.
3. **AppleScript `set body`** only for “Convert Whole Note from Markdown”, and only when the note has no attachments.

Nothing is stored in a parallel library. There is no sync engine.

## Uninstall

Quit NotesMD and delete `NotesMD.app`. Existing notes are untouched.

## Project layout

- `Sources/NotesMDCore` — Markdown ↔ Notes HTML, command planner
- `Sources/NotesMD` — overlay UI, Accessibility, Apple Events
- `Tests` — converter tests

```bash
make test
make app
```
