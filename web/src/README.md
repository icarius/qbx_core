# qbx_core multichar UI

React + Vite NUI panel for the character select/creation screen, replacing the old
`lib.registerContext`/`lib.inputDialog` (ox_lib) flow with a proper panel — same design
tokens/primitives as mGarage and qbx_rentals.

Talks to `client/character.lua`'s `openMultichar` NUI message and the
`qbx_core:multichar:preview` / `qbx_core:multichar:play` / `qbx_core:multichar:delete` /
`qbx_core:multichar:create` NUI callbacks — see `src/api.ts`. The 3D ped preview camera and
profanity/format validation stay in Lua; this only replaces the UI chrome.

## Develop

```bash
npm install
npm run dev
```

Outside the game, `src/mock.ts` stands in for the FiveM NUI bridge (`isEnvBrowser()` in
`src/nui.ts` is false in-game, so this never runs there).

## Build

```bash
npm run build
```

Outputs to `../build`, which `fxmanifest.lua`'s `ui_page` points at.
