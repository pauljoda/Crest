import { reader } from "../../reactive";

const readReadsDark = reader(
  (listener) => {
    const query = matchMedia("(prefers-color-scheme: dark)");
    query.addEventListener("change", listener);
    return () => query.removeEventListener("change", listener);
  },
  () => matchMedia("(prefers-color-scheme: dark)").matches,
);

/** Whether the device reads dark, which Setup's paper and room follow, followed by the expression that reads it. */
export function useReadsDark(): boolean {
  return readReadsDark();
}
