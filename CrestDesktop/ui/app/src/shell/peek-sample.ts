import { createContext } from "svelte";
import markup from "../../../../../CrestMac/Features/TransientBrowsing/Models/PeekSample.html?raw";

/** Opens the native Settings sample in the Peek belonging to this window. */
export const [getSamplePeek, setSamplePeek] = createContext<() => void>();
export const sampleAddress = "data:text/html;charset=utf-8," + encodeURIComponent(markup);
