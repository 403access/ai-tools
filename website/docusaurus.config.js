// @ts-check

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'OpenCodeBar',
  tagline: 'Watch, prompt, and start OpenCode sessions from your Mac and iPhone.',
  favicon: 'img/favicon.svg',

  url: 'https://403access.github.io',
  baseUrl: '/ai-tools/docs/',

  organizationName: '403access',
  projectName: 'ai-tools',
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

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl: 'https://github.com/403access/ai-tools/edit/main/website/',
          showLastUpdateAuthor: false,
          showLastUpdateTime: false,
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themes: [
    [
      require.resolve('@easyops-cn/docusaurus-search-local'),
      {
        hashed: true,
        language: ['en'],
        docsRouteBasePath: '/',
        indexBlog: false,
        highlightSearchTermsOnTargetPage: true,
        explicitSearchResultPath: true,
      },
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/screenshots/live.png',
      metadata: [
        {
          name: 'keywords',
          content:
            'OpenCode, macOS menu bar, iOS, iPadOS, OpenCodeBar Hub, SQLite, sessions, AI coding agent',
        },
        {
          name: 'description',
          content:
            'Documentation for OpenCodeBar: the macOS menu bar app, iPhone and iPad app, and the shared OpenCodeBar Hub.',
        },
      ],
      colorMode: {
        defaultMode: 'dark',
        disableSwitch: false,
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'OpenCodeBar',
        hideOnScroll: false,
        logo: {
          alt: 'OpenCodeBar',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'docs',
            position: 'left',
            label: 'Documentation',
          },
          {
            to: 'https://403access.github.io/ai-tools/',
            label: 'Website',
            position: 'left',
          },
          {
            href: 'https://github.com/403access/ai-tools',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Documentation',
            items: [
              { label: 'Getting started', to: '/getting-started/requirements' },
              { label: 'Using the apps', to: '/using/live' },
              { label: 'Hub reference', to: '/hub/architecture' },
            ],
          },
          {
            title: 'Project',
            items: [
              { label: 'GitHub', href: 'https://github.com/403access/ai-tools' },
              { label: 'Issues', href: 'https://github.com/403access/ai-tools/issues' },
              { label: 'OpenCode', href: 'https://opencode.ai' },
            ],
          },
          {
            title: 'More',
            items: [
              { label: 'Marketing site', href: 'https://403access.github.io/ai-tools/' },
              { label: 'README', href: 'https://github.com/403access/ai-tools#readme' },
              { label: 'Notes', href: 'https://github.com/403access/ai-tools/blob/main/NOTES.md' },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} OpenCodeBar. Built for OpenCode.`,
      },
      docs: {
        sidebar: {
          hideable: true,
          autoCollapseCategories: true,
        },
      },
      tableOfContents: {
        minHeadingLevel: 2,
        maxHeadingLevel: 3,
      },
      prism: {
        theme: require('prism-react-renderer').themes.github,
        darkTheme: require('prism-react-renderer').themes.dracula,
        additionalLanguages: ['bash', 'json', 'typescript', 'swift'],
      },
    }),
};

module.exports = config;
