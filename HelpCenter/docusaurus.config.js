const {themes: prismThemes} = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Crest Help',
  tagline: 'Guides for browsing under your colors.',
  favicon: 'img/crest-logo.svg',
  url: 'https://crestbrowser.com',
  baseUrl: '/guides/',
  organizationName: 'pauljoda',
  projectName: 'Crest-Website',
  trailingSlash: true,
  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },
  plugins: [require.resolve('./plugins/help-search-index')],
  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          breadcrumbs: true,
          showLastUpdateAuthor: false,
          showLastUpdateTime: false,
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
        sitemap: {
          changefreq: 'weekly',
          priority: 0.7,
        },
      },
    ],
  ],
  themeConfig: {
    image: 'https://crestbrowser.com/assets/og-card-brand.jpg',
    metadata: [
      {
        name: 'description',
        content: 'Crest help and guides for Spaces, extensions, passwords, and everyday browsing.',
      },
    ],
    colorMode: {
      defaultMode: 'light',
      disableSwitch: true,
      respectPrefersColorScheme: false,
    },
    navbar: {
      title: 'Crest Help',
      logo: {
        alt: 'Crest',
        src: 'img/crest-logo.svg',
      },
      items: [
        {type: 'docSidebar', sidebarId: 'helpSidebar', position: 'left', label: 'Guides'},
        {to: '/extension-compatibility/', label: 'Compatibility', position: 'left'},
        {href: 'https://crestbrowser.com/support/', label: 'Support', position: 'right'},
        {href: 'https://crestbrowser.com/', label: 'Product site', position: 'right'},
      ],
    },
    docs: {
      sidebar: {
        hideable: true,
        autoCollapseCategories: false,
      },
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Crest',
          items: [
            {label: 'Product site', href: 'https://crestbrowser.com/'},
            {label: 'Join TestFlight', href: 'https://testflight.apple.com/join/vV1CM49Q'},
          ],
        },
        {
          title: 'Help',
          items: [
            {label: 'All guides', to: '/'},
            {label: 'Extension compatibility', to: '/extension-compatibility/'},
            {label: 'Support', href: 'https://crestbrowser.com/support/'},
          ],
        },
        {
          title: 'Community',
          items: [
            {label: 'r/CrestBrowser', href: 'https://www.reddit.com/r/CrestBrowser'},
            {label: 'Privacy', href: 'https://crestbrowser.com/privacy/'},
          ],
        },
      ],
      copyright: `Crest is independent and not affiliated with Arc. © ${new Date().getFullYear()} Paul Davis.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  },
};

module.exports = config;
