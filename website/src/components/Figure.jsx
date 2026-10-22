import React from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';

export default function Figure({src, alt, caption, className = '', width}) {
  return (
    <figure className={`docsFigure ${className}`.trim()}>
      <img
        src={useBaseUrl(src)}
        alt={alt}
        loading="lazy"
        style={width ? {width} : undefined}
      />
      {caption ? <figcaption>{caption}</figcaption> : null}
    </figure>
  );
}
