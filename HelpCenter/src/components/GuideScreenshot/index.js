import React from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';

export default function GuideScreenshot({src, alt, caption}) {
  return (
    <figure className="guide-screenshot">
      <img src={useBaseUrl(src)} alt={alt} loading="lazy" />
      {caption && <figcaption>{caption}</figcaption>}
    </figure>
  );
}
