# Badge apps

Apps for the AtomVM conference badge, installed from the badge's Store page.

Each app lives in `apps/<id>/`: its code under `lib/`, every module inside
`Badge.App.<Id>`, and its page module `Badge.App.<Id>.Page`. `app.exs` holds
its store entry:

    [name: "Fractals", author: "…", description: "…", version: "1.0.0", storage: "ram"]

`id` is a lowercase letter and up to 14 lowercase letters or digits.

## Publishing

This project needs `avm_badge` checked out next to it.

    BADGE_STORE_KEY=~/.config/avm_badge/store_key mix store.pack <id>
    git add packs manifest.json && git commit && git push

Badges see a push within about five minutes. A published version is never
rebuilt with different bytes: bump `version` instead.
