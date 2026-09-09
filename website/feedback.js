(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.LfsFeedback = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const REPOSITORY = "mitzracing/live-for-speed-linux";
  const MAX_HANDOFF_URL = 7500;
  const FORM_FIELD_NAMES = Object.freeze([
    "kind",
    "summary",
    "distribution",
    "distributionVersion",
    "packageMethod",
    "wrapperVersion",
    "desktop",
    "graphics",
    "details",
    "expected",
    "steps",
    "value",
    "diagnostics",
    "safety",
  ]);
  const TYPE_CONFIG = Object.freeze({
    bug: {
      template: "bug.yml",
      titlePrefix: "[Bug]: ",
      fields: {
        distribution: "distribution",
        distributionVersion: "distribution_version",
        wrapperVersion: "wrapper_version",
        desktop: "desktop",
        graphics: "graphics",
        details: "problem",
        expected: "expected",
        steps: "steps",
        diagnostics: "diagnostics",
      },
    },
    compatibility: {
      template: "compatibility.yml",
      titlePrefix: "[Compatibility]: ",
      fields: {
        distribution: "distribution",
        distributionVersion: "distribution_version",
        packageMethod: "package_method",
        desktop: "desktop",
        graphics: "graphics",
        details: "result",
        steps: "reproduction",
        diagnostics: "diagnostics",
      },
    },
    feature: {
      template: "feature.yml",
      titlePrefix: "[Feature]: ",
      fields: {
        details: "problem",
        expected: "proposal",
        value: "value",
        steps: "alternatives",
      },
    },
    feedback: {
      template: "feedback.yml",
      titlePrefix: "[Feedback]: ",
      fields: {
        details: "worked",
        expected: "improve",
        value: "outcome",
      },
    },
  });

  const REGISTRY_MARKER = /(?:WINE REGISTRY Version|Windows Registry Editor Version|(?:^|\n)\s*\[?HKEY_(?:CURRENT_USER|LOCAL_MACHINE|CLASSES_ROOT|USERS|CURRENT_CONFIG))/im;
  const REDACTIONS = Object.freeze([
    {
      category: "private key",
      pattern: /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/gi,
      replacement: "[redacted private key]",
    },
    {
      category: "access token",
      pattern: /\bgh[pousr]_[A-Za-z0-9_]{20,}\b/gi,
      replacement: "[redacted access token]",
    },
    {
      category: "authorization value",
      pattern: /\bBearer\s+[A-Za-z0-9._~+/=-]{16,}/gi,
      replacement: "Bearer [redacted]",
    },
    {
      category: "credential value",
      pattern: /^(\s*(?:password|passwd|authorization|cookie|token|access[_ -]?key|secret|unlock(?:\s+code)?|account(?:\s+(?:name|id|key))?)\s*[:=]\s*).+$/gim,
      replacement: "$1[redacted]",
    },
    {
      category: "machine identifier",
      pattern: /^(\s*(?:machine[- ]?id|hardware\s+serial|serial\s+number)\s*[:=]\s*).+$/gim,
      replacement: "$1[redacted]",
    },
    {
      category: "Linux or macOS home path",
      pattern: /\/(?:home|Users)\/[^/\s"'<>]+(?:\/[^\s"'<>]*)?/g,
      replacement: "$HOME/[redacted]",
    },
    {
      category: "Windows home path",
      pattern: /\b[A-Za-z]:\\Users\\[^\\\s"'<>]+(?:\\[^\s"'<>]*)?/gi,
      replacement: "%USERPROFILE%\\[redacted]",
    },
    {
      category: "email address",
      pattern: /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi,
      replacement: "[redacted email]",
    },
  ]);

  function normalizeText(value) {
    return String(value || "").replace(/\r\n?/g, "\n").trim();
  }

  function sanitizeText(value) {
    let text = normalizeText(value);
    const categories = [];
    if (REGISTRY_MARKER.test(text)) {
      return { value: "[redacted registry content]", categories: ["registry content"] };
    }
    for (const rule of REDACTIONS) {
      rule.pattern.lastIndex = 0;
      if (rule.pattern.test(text)) {
        categories.push(rule.category);
        rule.pattern.lastIndex = 0;
        text = text.replace(rule.pattern, rule.replacement);
      }
    }
    return { value: text, categories: [...new Set(categories)] };
  }

  function sanitizeFields(values) {
    const fields = {};
    const categories = [];
    for (const [name, value] of Object.entries(values)) {
      if (name === "safety") continue;
      const result = sanitizeText(value);
      fields[name] = result.value;
      categories.push(...result.categories);
    }
    return { fields, categories: [...new Set(categories)].sort() };
  }

  function requiredFieldNames(kind) {
    const common = ["summary", "details", "expected"];
    if (kind === "bug") {
      return common.concat("distribution", "distributionVersion", "wrapperVersion", "desktop", "graphics", "steps");
    }
    if (kind === "compatibility") {
      return common.concat("distribution", "distributionVersion", "packageMethod", "desktop", "graphics", "steps");
    }
    if (kind === "feature") return common.concat("value");
    return common;
  }

  function validateFields(kind, fields) {
    if (!TYPE_CONFIG[kind]) throw new Error("Choose a report type.");
    for (const name of requiredFieldNames(kind)) {
      if (!normalizeText(fields[name])) throw new Error("Complete every required field before handoff.");
    }
  }

  function feedbackEnvironment(fields) {
    return [fields.distribution, fields.distributionVersion, fields.desktop, fields.graphics]
      .filter(Boolean)
      .join(" · ");
  }

  function buildPreview(kind, title, fields) {
    const labels = {
      distribution: "Linux distribution",
      distributionVersion: "Distribution and version",
      packageMethod: "Installation method",
      wrapperVersion: "Wrapper version",
      desktop: "Desktop and display session",
      graphics: "GPU and driver",
      details: "Observed result or player problem",
      expected: "Expected result or proposed improvement",
      steps: "Reproduction or verification steps",
      value: "Desired outcome or user value",
      diagnostics: "Sanitized diagnostics",
    };
    const sections = Object.entries(labels)
      .filter(([name]) => fields[name])
      .map(([name, label]) => `### ${label}\n\n${fields[name]}`);
    return `# ${title}\n\nReport type: ${kind}\n\n${sections.join("\n\n")}`;
  }

  function buildHandoff(values) {
    if (!values.safety) throw new Error("Confirm the public-data check before handoff.");
    const kind = normalizeText(values.kind);
    const config = TYPE_CONFIG[kind];
    if (!config) throw new Error("Choose a report type.");
    const sanitized = sanitizeFields(values);
    validateFields(kind, sanitized.fields);

    const title = `${config.titlePrefix}${sanitized.fields.summary}`.slice(0, 120);
    const queryFields = { ...sanitized.fields };
    if (kind === "compatibility") {
      queryFields.details = `${queryFields.details}\n\nExpected result:\n${queryFields.expected}`;
    }
    const url = new URL(`https://github.com/${REPOSITORY}/issues/new`);
    url.searchParams.set("template", config.template);
    url.searchParams.set("title", title);
    for (const [sourceName, targetName] of Object.entries(config.fields)) {
      const value = queryFields[sourceName];
      if (value) url.searchParams.set(targetName, value);
    }
    if (kind === "feedback") {
      const environment = feedbackEnvironment(sanitized.fields);
      if (environment) url.searchParams.set("environment", environment);
    }
    if (url.href.length > MAX_HANDOFF_URL) {
      throw new Error("The report is too long for a safe GitHub handoff. Shorten diagnostics or reproduction steps.");
    }
    return {
      kind,
      title,
      url: url.href,
      fields: sanitized.fields,
      redactions: sanitized.categories,
      preview: buildPreview(kind, title, sanitized.fields),
    };
  }

  function setConditionalRequirements(form, kind) {
    const environmentRequired = kind === "bug" || kind === "compatibility";
    for (const name of ["distribution", "distributionVersion", "desktop", "graphics", "steps"]) {
      form.elements[name].required = environmentRequired;
    }
    form.elements.wrapperVersion.required = kind === "bug";
    form.elements.packageMethod.required = kind === "compatibility";
    form.elements.value.required = kind === "feature";
    form.querySelector("[data-package-method]").hidden = kind !== "compatibility";
    form.querySelector("[data-wrapper-version]").hidden = kind !== "bug";
    const environment = form.querySelector("#feedback-environment");
    if (environment) {
      environment.open = environmentRequired;
      environment.querySelector("#environment-requirement").textContent = environmentRequired
        ? "Required for this report"
        : "Optional";
    }
  }

  function setupFeedbackForm(documentObject) {
    const form = documentObject.getElementById("feedback-form");
    if (!form) return;
    const result = documentObject.getElementById("feedback-result");
    const status = documentObject.getElementById("feedback-status");
    const handoff = documentObject.getElementById("github-handoff");
    const preview = documentObject.getElementById("report-preview");
    const disclosure = documentObject.getElementById("feedback-disclosure");
    const summaryLabel = documentObject.getElementById("feedback-summary-label");
    const collapseButton = documentObject.getElementById("collapse-feedback");
    const kindLabels = {
      bug: "Report something broken",
      compatibility: "Report distribution compatibility",
      feature: "Suggest an improvement",
      feedback: "Share your experience",
    };

    function updateDisclosureState() {
      for (const button of documentObject.querySelectorAll("[data-feedback-kind]")) {
        button.setAttribute("aria-expanded", String(disclosure.open));
      }
    }

    function selectKind(kind) {
      form.elements.kind.value = kind;
      summaryLabel.textContent = kindLabels[kind];
      disclosure.open = true;
      setConditionalRequirements(form, kind);
      updateDisclosureState();
      form.elements.summary.focus();
    }

    for (const button of documentObject.querySelectorAll("[data-feedback-kind]")) {
      button.addEventListener("click", () => selectKind(button.dataset.feedbackKind));
    }
    disclosure.addEventListener("toggle", updateDisclosureState);
    collapseButton.addEventListener("click", () => {
      disclosure.open = false;
      disclosure.querySelector("summary").focus();
    });
    form.elements.kind.addEventListener("change", () => {
      const kind = form.elements.kind.value;
      summaryLabel.textContent = kindLabels[kind];
      setConditionalRequirements(form, kind);
    });
    setConditionalRequirements(form, form.elements.kind.value);
    updateDisclosureState();

    // Native validation must be able to focus a required field inside a closed disclosure.
    form.addEventListener("invalid", (event) => {
      for (let group = event.target.closest("details"); group; group = group.parentElement?.closest("details")) {
        group.open = true;
      }
    }, true);

    form.addEventListener("submit", (event) => {
      event.preventDefault();
      result.hidden = true;
      try {
        const values = Object.fromEntries(
          FORM_FIELD_NAMES.map((name) => {
            const field = form.elements[name];
            const value = field.type === "checkbox" ? (field.checked ? field.value : "") : field.value;
            return [name, value];
          }),
        );
        const handoffPlan = buildHandoff(values);
        for (const [name, value] of Object.entries(handoffPlan.fields)) {
          if (form.elements[name] && typeof form.elements[name].value === "string") form.elements[name].value = value;
        }
        handoff.href = handoffPlan.url;
        preview.textContent = handoffPlan.preview;
        status.textContent = handoffPlan.redactions.length
          ? `Removed before handoff: ${handoffPlan.redactions.join(", ")}. Review the redacted report, then continue to GitHub.`
          : "No known sensitive-data pattern was detected. Review the report, then continue to GitHub.";
        status.dataset.state = handoffPlan.redactions.length ? "redacted" : "clean";
        result.hidden = false;
        handoff.focus();
      } catch (error) {
        status.textContent = error instanceof Error ? error.message : "Could not prepare the report.";
        status.dataset.state = "error";
        result.hidden = false;
      }
    });
  }

  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", () => setupFeedbackForm(document));
    } else {
      setupFeedbackForm(document);
    }
  }

  return Object.freeze({ buildHandoff, sanitizeFields, sanitizeText, setupFeedbackForm });
});
