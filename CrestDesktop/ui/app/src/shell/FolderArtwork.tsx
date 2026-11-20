import type { BrandColor } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { animate, motion, useMotionValue, useTransform } from "motion/react";
import { useEffect } from "react";

import { css, emojiOf, toneOver } from "../branding";
import { Symbol } from "../symbols";

/** The folder's footprint, a folder symbol's at the sidebar's row size. */
const width = 18;
const height = 14;
/** BrowserFolderGeometry. */
const geometry = { translation: 3, yAngle: 32, frontAngle: -30, backAngle: 28, perspective: 350, tabHeight: 0.25, tabStart: 0.42, tabEnd: 0.58, cornerDivisor: 7 };

/**
 * The Mac's BrowserFolderFaces: a folder drawn as two flat faces in its own
 * colour, the back a shade darker with its tab, the front lit a little and
 * wearing the folder's emoji or symbol; opening the folder swings the faces
 * apart about their foot, as a folder opens.
 */
export function FolderArtwork({ symbol, color, expanded }: { symbol: string; color: BrandColor; expanded: boolean }) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const transition = reduce ? { duration: 0 } : tokens.collection;
  const inset = 0.5;
  const w = width - inset * 2;
  const h = height - inset * 2;
  const top = height * geometry.tabHeight;
  const shoulder = top / 1.5;
  const radius = width / geometry.cornerDivisor;
  const back = [
    `M ${radius} 0`, `L ${w * geometry.tabStart} 0`, `L ${w * geometry.tabEnd} ${shoulder}`, `L ${w - radius} ${shoulder}`,
    `A ${radius} ${radius} 0 0 1 ${w} ${shoulder + radius}`, `L ${w} ${h - radius}`,
    `A ${radius} ${radius} 0 0 1 ${w - radius} ${h}`, `L ${radius} ${h}`, `A ${radius} ${radius} 0 0 1 0 ${h - radius}`,
    `L 0 ${radius}`, `A ${radius} ${radius} 0 0 1 ${radius} 0`, "Z",
  ].join(" ");
  const frontHeight = Math.max(1, height - top);
  const fill = css(color);
  const ink = toneOver(color) === "light" ? "white" : "black";
  const emoji = emojiOf(symbol);
  const glyph = emoji ?? (symbol !== "folder" && symbol !== "folder.fill" ? symbol : null);
  // One openness drives both faces, the transform written out in the Mac's
  // order: tilted about the foot, turned, nudged along, in perspective.
  const openness = useMotionValue(expanded ? 1 : 0);
  useEffect(() => {
    const controls = animate(openness, expanded ? 1 : 0, transition);
    return () => controls.stop();
    // The transition follows Reduce Motion, read as the folder changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expanded, openness]);
  const backTransform = useTransform(openness, (o) => faceTransform(o, geometry.backAngle));
  const frontTransform = useTransform(openness, (o) => faceTransform(o, geometry.frontAngle));
  return (
    <span className="folder-artwork" style={{ width, height }} aria-hidden>
      <motion.svg className="folder-face" width={width} height={height} viewBox={`${-inset} ${-inset} ${width} ${height}`}
        style={{ transform: backTransform, transformOrigin: "0 100%" }}>
        <path d={back} fill={fill} />
        <path d={back} fill="black" fillOpacity={0.22} />
      </motion.svg>
      <motion.span className="folder-face front" style={{ height: frontHeight, transform: frontTransform, transformOrigin: "0 100%", color: ink }}>
        <svg width={width} height={frontHeight} viewBox={`0 0 ${width} ${frontHeight}`}>
          <rect x={inset} y={inset} width={width - inset * 2} height={frontHeight - inset * 2} rx={Math.max(0, radius - inset)} fill={fill} />
          <rect x={inset} y={inset} width={width - inset * 2} height={frontHeight - inset * 2} rx={Math.max(0, radius - inset)} fill="white" fillOpacity={0.12} />
        </svg>
        {glyph && (
          <span className="folder-glyph" style={{ fontSize: frontHeight * 0.5 }}>
            {emoji ?? <Symbol name={glyph} size={Math.round(frontHeight * 0.55)} strokeWidth={2.5} />}
          </span>
        )}
      </motion.span>
    </span>
  );
}

/** BrowserFolderFaceProjection at `openness`: tilted about the foot, turned, nudged along, in perspective. */
function faceTransform(openness: number, tilt: number): string {
  return `perspective(${geometry.perspective}px) translateX(${geometry.translation * openness}px) rotateY(${geometry.yAngle * openness}deg) rotateX(${tilt * openness}deg)`;
}
