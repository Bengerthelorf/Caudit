import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Claudit',
  description: 'Claude API usage tracker for your macOS menu bar',
  base: '/Claudit/',

  head: [
    ['link', { rel: 'icon', type: 'image/png', href: '/Claudit/icon.png' }],
  ],

  themeConfig: {
    logo: '/icon.png',

    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Download', link: 'https://github.com/Bengerthelorf/Claudit/releases/latest' },
    ],

    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Getting Started', link: '/guide/getting-started' },
          { text: 'Features', link: '/guide/features' },
          { text: 'Remote Devices', link: '/guide/remote-devices' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/Bengerthelorf/Claudit' },
    ],

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2026 Bengerthelorf',
    },

    editLink: {
      pattern: 'https://github.com/Bengerthelorf/Claudit/edit/main/docs/:path',
    },

    search: {
      provider: 'local',
    },
  },
})
