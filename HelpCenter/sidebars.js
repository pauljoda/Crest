/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  helpSidebar: [
    'index',
    {
      type: 'category',
      label: 'Install extensions',
      collapsed: false,
      items: [
        'extensions/install-chrome-web-store',
        'extensions/install-firefox-add-ons',
        'extensions/scan-safari-web-extensions',
      ],
    },
    {
      type: 'category',
      label: 'Manage a Space',
      collapsed: false,
      items: [
        'extensions/manage-permissions-site-access',
        'extensions/pin-and-use-popups',
        'extensions/keyboard-shortcuts',
        'spaces/crest-passwords',
      ],
    },
    {
      type: 'category',
      label: 'Compatibility & troubleshooting',
      collapsed: false,
      items: [
        'extensions/status-and-technical-details',
        'extensions/native-companion-limits',
        'extensions/compatibility',
        'extensions/troubleshoot-partial-compatibility',
        'extensions/onepassword',
        'extensions/icloud-passwords',
      ],
    },
  ],
};

module.exports = sidebars;
