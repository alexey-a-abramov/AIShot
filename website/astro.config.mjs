import { defineConfig } from 'astro/config';

// AIShot marketing/docs site. Localized into English, French, and Spanish via
// Astro's built-in i18n routing (add a locale here + a page folder to extend).
export default defineConfig({
  site: 'https://aishot.app',
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'fr', 'es'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
});
