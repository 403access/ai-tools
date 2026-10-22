// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    'intro',
    {
      type: 'category',
      label: 'Getting started',
      link: { type: 'doc', id: 'getting-started/requirements' },
      items: [
        'getting-started/requirements',
        'getting-started/install-hub',
        'getting-started/mac-app',
        'getting-started/ios-app',
        'getting-started/pairing',
      ],
    },
    {
      type: 'category',
      label: 'Using OpenCodeBar',
      link: { type: 'doc', id: 'using/live' },
      items: [
        'using/live',
        'using/session',
        'using/projects',
        'using/usage',
        'using/settings',
        'using/voice',
      ],
    },
    {
      type: 'category',
      label: 'OpenCodeBar Hub',
      link: { type: 'doc', id: 'hub/architecture' },
      items: [
        'hub/architecture',
        'hub/configuration',
        'hub/api',
        'hub/security',
        'hub/go-usage',
      ],
    },
    {
      type: 'category',
      label: 'Development',
      link: { type: 'doc', id: 'development/build' },
      items: [
        'development/build',
        'development/make-targets',
        'development/testing',
        'development/project-layout',
        'development/screenshots',
        'development/docs-site',
      ],
    },
    {
      type: 'category',
      label: 'Help',
      link: { type: 'doc', id: 'help/troubleshooting' },
      items: ['help/troubleshooting', 'help/faq', 'help/limitations'],
    },
  ],
};

module.exports = sidebars;
