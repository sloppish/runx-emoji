# runx-emoji

A [Runx](https://github.com/sloppish/runx) plugin for searching and inserting emoji using macOS's weighted CoreEmoji index.

Type what you mean, get the relevant emoji.

## Usage

Open Runx and type:

```
emoji like          → search and type 👍
emoji-copy smile    → search and copy an emoji
```

Select a result to type it into the previous app. Use `emoji-copy` to copy it to the clipboard instead.

## Aliases

You can define aliases for commands in your Runx plugin config, for example:

```toml
[plugin.emoji.aliases]
emoji = "e"
emoji-copy = "ec"
```

This lets you type `e like` instead of `emoji like`.

## Local index

The first search automatically generates `emoji-search.json` from the CoreEmoji resources installed on your Mac. The generated file is reused by later searches and is not distributed with the plugin.

To refresh it after a macOS update:

```sh
./tools/emoji-index-exporter emoji-search.json
```

## Requirements

- macOS
- CoreEmoji resources compatible with the bundled exporter

The exporter uses an undocumented, unsupported private macOS component. Apple may change or remove it in a future macOS release. Do not redistribute the generated JSON unless you have the necessary rights under Apple's terms and applicable law.
