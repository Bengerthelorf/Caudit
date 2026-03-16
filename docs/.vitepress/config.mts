import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Caudit',
  description: 'Claude API usage tracker for your macOS menu bar',
  base: '/Caudit/',

  head: [
    ['link', { rel: 'icon', type: 'image/png', href: '/Caudit/icon.png' }],
  ],

  themeConfig: {
    logo: '/icon.png',

    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Download', link: 'https://github.com/Bengerthelorf/Caudit/releases/latest' },
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
      { icon: 'github', link: 'https://github.com/Bengerthelorf/Caudit' },
    ],

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2026 Bengerthelorf',
    },

    editLink: {
      pattern: 'https://github.com/Bengerthelorf/Caudit/edit/main/docs/:path',
    },

    search: {
      provider: 'local',
    },
  },
})
