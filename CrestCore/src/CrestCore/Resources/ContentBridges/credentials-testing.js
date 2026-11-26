    ,
    inspectForTesting(selector) {
      const selectedRoot = document.querySelector(selector);
      const root = selectedRoot?.shadowRoot || selectedRoot;
      if (!root) return null;
      const reading = read(root);
      return { formID: reading.formID, readingID: reading.readingID, fields: reading.fields };
    },
    captureForTesting(selector) {
      const selectedRoot = document.querySelector(selector);
      const root = selectedRoot?.shadowRoot || selectedRoot;
      if (!root) return false;
      capture(root, "submit", null);
      return true;
    },
    focusForTesting(selector) {
      const input = document.querySelector(selector);
      if (!isReadable(input)) return false;
      return reportFocus(input);
    }