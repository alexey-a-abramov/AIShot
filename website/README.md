# AIShot website

Marketing/docs site for AIShot, built with [Astro](https://astro.build) and
localized into **English, French, and Spanish** via Astro's built-in i18n.

## Develop

```bash
cd website
npm install
npm run dev      # http://localhost:4321
npm run build    # static output in dist/
```

## Structure

- `src/i18n/ui.ts` — all translatable copy (one object per locale).
- `src/components/Home.astro` — the page, rendered per locale.
- `src/pages/index.astro` (en), `src/pages/fr/`, `src/pages/es/` — locale routes.
- `astro.config.mjs` — i18n config (`en` default, `fr`, `es`).

## Add a language

1. Add the locale to `locales` in `astro.config.mjs`.
2. Add an entry to `languages` and `ui` in `src/i18n/ui.ts`.
3. Add `src/pages/<lang>/index.astro` mirroring the others.
