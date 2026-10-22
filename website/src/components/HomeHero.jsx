import React from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';

export default function HomeHero() {
  return (
    <header className="docsHero">
      <div className="docsHeroGlow" aria-hidden="true" />
      <img
        className="docsHeroLogo"
        src={useBaseUrl('/img/logo.svg')}
        alt=""
        width="72"
        height="72"
      />
      <p className="docsHeroEyebrow">macOS · iPhone · iPad · Local hub</p>
      <h1>OpenCodeBar documentation</h1>
      <p className="docsHeroLede">
        Watch and control OpenCode from a native macOS menu bar app and an
        iPhone/iPad app, backed by one local Bun + SQLite hub.
      </p>
      <div className="docsHeroActions">
        <Link className="button button--primary button--lg" to="/getting-started/install-hub">
          Install the hub
        </Link>
        <Link className="button button--secondary button--lg" to="/using/live">
          Explore the apps
        </Link>
        <Link className="button button--outline button--lg" to="/hub/api">
          API reference
        </Link>
      </div>
    </header>
  );
}
