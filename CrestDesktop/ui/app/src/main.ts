import { cssVariables } from "@crest/design";
import { mount } from "svelte";

import App from "./App.svelte";
import "./styles.css";

for (const [name, value] of Object.entries(cssVariables())) document.documentElement.style.setProperty(name, value);

mount(App, { target: document.getElementById("root")! });
