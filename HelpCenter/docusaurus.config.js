const {themes: prismThemes} = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Crest Help',
  tagline: 'Help articles for Crest.',
  favicon: 'img/crest-favicon.svg',
  url: 'https://crestbrowser.com',
  baseUrl: '/guides/',
  organizationName: 'crest-browser',
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
  headTags: [
    {tagName: 'link', attributes: {rel: 'icon', href: '/favicon.ico', sizes: '48x48'}},
    {tagName: 'link', attributes: {rel: 'apple-touch-icon', href: '/assets/apple-touch-icon.png'}},
  ],
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
    image: 'https://crestbrowser.com/assets/og-card.jpg',
    metadata: [
      {
        name: 'description',
        content: 'Help articles for Crest on Mac, iPad, and iPhone.',
      },
      {name: 'theme-color', content: '#FBF5E6'},
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
        {type: 'docSidebar', sidebarId: 'helpSidebar', position: 'left', label: 'Articles'},
        {to: '/keyboard-shortcuts/', label: 'Shortcuts', position: 'left'},
        {to: '/extension-api-compatibility/', label: 'Compatibility', position: 'left'},
        {href: 'https://crestbrowser.com/', label: 'Product site', position: 'right'},
        {href: 'https://crestbrowser.com/support/', label: 'Support', position: 'right'},
        {href: 'https://github.com/crest-browser/Crest/releases/latest', label: 'Download for Mac', position: 'right', className: 'navbar-download'},
      ],
    },
    docs: {
      sidebar: {
        hideable: true,
        autoCollapseCategories: false,
      },
    },
    footer: {
      style: 'light',
      links: [
        {
          title: 'Crest',
          items: [
            {label: 'Product site', href: 'https://crestbrowser.com/'},
            {label: 'Download for Mac', href: 'https://github.com/crest-browser/Crest/releases/latest'},
            {label: 'iPhone & iPad TestFlight', href: 'https://testflight.apple.com/join/vV1CM49Q'},
          ],
        },
        {
          title: 'Help',
          items: [
            {label: 'All articles', to: '/'},
            {label: 'Keyboard shortcuts', to: '/keyboard-shortcuts/'},
            {label: 'Split View', to: '/split-view/'},
            {label: 'Extension compatibility', to: '/extension-api-compatibility/'},
            {label: 'Support', href: 'https://crestbrowser.com/support/'},
          ],
        },
        {
          title: 'Community',
          items: [
            {label: 'GitHub Issues', href: 'https://github.com/crest-browser/Crest/issues/new/choose'},
            {label: 'r/CrestBrowser', href: 'https://www.reddit.com/r/CrestBrowser'},
            {label: 'Discord', href: 'https://discord.gg/gjrM5qMB6x'},
            {label: 'Donate', href: 'https://ko-fi.com/pauljoda/tiers'},
            {label: 'Privacy', href: 'https://crestbrowser.com/privacy/'},
            {label: 'Press kit', href: 'https://crestbrowser.com/press/'},
          ],
        },
      ],
      copyright: `© ${new Date().getFullYear()} Paul Davis.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  },
};

module.exports = config;
