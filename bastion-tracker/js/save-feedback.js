/** Shared wording for every save. Practice saves never use the server's "Saved" line. */

export const COMMIT_ACTIONS = ["accept-review", "accept-remaining", "remove-goods", "remove-person"];

export function beginSave(source) {
  return { status: "pending", source: source || "", message: "Saving…" };
}

export function succeedSave({ practice, summary, replay }) {
  const lead = practice ? "Saved on this device (practice)" : "Saved";
  const detail = replay ? "Already recorded." : String(summary || "").trim();
  return {
    status: "success",
    source: "",
    message: detail ? `${lead}: ${detail}` : lead,
  };
}

export function failSave(message, source) {
  return {
    status: "failure",
    source: source || "",
    message: message || "That was not saved.",
  };
}

function disablesCommit(attrs) {
  if (/\bdisabled\b/.test(attrs)) return false;
  if (/type="submit"/.test(attrs)) return true;
  const action = (attrs.match(/data-action="([^"]+)"/) || [])[1];
  return COMMIT_ACTIONS.includes(action);
}

export function markSavingButtons(html, source) {
  if (!source) return html;
  let out = html.replace(/<button\b([^>]*)>/g, (match, attrs) => {
    if (!disablesCommit(attrs)) return match;
    return `<button${attrs} disabled>`;
  });
  let pattern;
  if (source.startsWith("accept-review:")) {
    const index = source.slice("accept-review:".length);
    pattern = new RegExp(`(<button\\b[^>]*data-action="accept-review"[^>]*data-index="${index}"[^>]*>)[\\s\\S]*?(</button>)`);
  } else if (source.startsWith("remove-goods:") || source.startsWith("remove-person:")) {
    const splitAt = source.indexOf(":");
    const action = source.slice(0, splitAt);
    const id = source.slice(splitAt + 1);
    pattern = new RegExp(`(<button\\b[^>]*data-action="${action}"[^>]*data-id="${id}"[^>]*>)[\\s\\S]*?(</button>)`);
  } else if (COMMIT_ACTIONS.includes(source)) {
    pattern = new RegExp(`(<button\\b[^>]*data-action="${source}"[^>]*>)[\\s\\S]*?(</button>)`);
  } else {
    pattern = new RegExp(`(<form\\b[^>]*\\bid="${source}"[^>]*>[\\s\\S]*?<button\\b[^>]*>)[\\s\\S]*?(</button>)`);
  }
  return out.replace(pattern, "$1Saving…$2");
}
