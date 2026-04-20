export default {
  slug: 'claudit',
  install: {
    macos: { name: 'macOS',  cmd: 'brew install Bengerthelorf/tap/claudit', note: 'homebrew; universal binary — arm64 + x86_64' },
    dmg:   { name: 'DMG',    cmd: 'open https://github.com/Bengerthelorf/Claudit/releases/latest', note: 'download, drag to /Applications, launch' },
  },
  sections: [
    {
      label: 'guide',
      items: ['getting-started', 'features', 'remote-devices'],
    },
  ],
  linkRewrites: {
    '/guide/': '/docs/',
  },
};
