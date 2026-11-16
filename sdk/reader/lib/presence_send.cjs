// Presence's sender (xenia#20): each approved interaction sent from the
// witness's own signed-in Chrome profile, from the origin that owns it,
// exactly as Oneiroi handed it. No model touches the words.
//
//   node presence_send.cjs <due.json> <chrome profile dir>
//
// due.json is Oneiroi's /reader/presence answer: [{number, action, target,
// id, host, url, text}]. Prints [{number, status, ok, url, reason}].
//
// Endpoints, verified 2026-11-15 on the witness's own post by the probe
// (each undone straight after): a post's like, POST/DELETE
// <host>/api/v1/post/<id>/reaction {reaction: "❤"} from the publication's
// own origin; a restack, POST/DELETE substack.com/api/v1/restack/feed
// {postId|commentId, tabId, surface} from substack.com. Not yet verified
// by a run of ours, from the shapes a maintained client uses: a post's
// comment (POST <host>/api/v1/post/<id>/comment {body}), a note's like
// (POST substack.com/api/v1/comment/<id>/reaction) and a reply to a note
// (POST substack.com/api/v1/comment/feed {bodyJson, parent_id}). A shape
// Substack refuses comes back failed with its status, never retried.
'use strict';

const fs = require('fs');
const path = require('path');

const root = process.env.ONEIROI_READER_NODE || path.join(__dirname, '..', 'node', 'node_modules');
const { chromium } = require(path.join(root, 'playwright-core'));

const SUBSTACK = 'https://substack.com';

function request(item) {
  const restack = {
    postId: item.target === 'post' ? item.id : null,
    commentId: item.target === 'note' ? item.id : null,
    tabId: 'for-you',
    surface: 'feed',
  };

  switch (`${item.target}:${item.action}`) {
    case 'post:like':
      return { origin: item.host, url: `/api/v1/post/${item.id}/reaction`, body: { reaction: '❤' } };
    case 'post:comment':
      return { origin: item.host, url: `/api/v1/post/${item.id}/comment`, body: { body: item.text } };
    case 'note:like':
      return { origin: SUBSTACK, url: `/api/v1/comment/${item.id}/reaction`, body: { reaction: '❤' } };
    case 'note:comment':
      return {
        origin: SUBSTACK,
        url: '/api/v1/comment/feed',
        body: {
          bodyJson: { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: item.text }] }] },
          parent_id: item.id,
        },
      };
    case 'post:restack':
    case 'note:restack':
      return { origin: SUBSTACK, url: '/api/v1/restack/feed', body: restack };
    default:
      return null;
  }
}

// Where the interaction now is, when Substack's answer names it.
function address(item, answer) {
  const id = answer && typeof answer === 'object' ? answer.id : null;
  if (item.action === 'comment' && id && item.target === 'post') return `${item.url}/comment/${id}`;
  if (item.action === 'comment' && id) return `${SUBSTACK}/note/c-${id}`;
  return item.url;
}

async function main() {
  const [, , duePath, profile] = process.argv;
  const due = JSON.parse(fs.readFileSync(duePath, 'utf8'));
  const results = [];
  const context = await chromium.launchPersistentContext(profile, { channel: 'chrome', headless: true });
  const page = context.pages()[0] || (await context.newPage());

  try {
    for (const item of due) {
      const req = request(item);
      if (!req) {
        results.push({ number: item.number, status: null, ok: false, reason: `no way to send a ${item.action} on a ${item.target}` });
        continue;
      }
      try {
        if (new URL(page.url() || 'about:blank').origin !== req.origin) {
          await page.goto(req.origin === SUBSTACK ? `${SUBSTACK}/home` : item.url, { waitUntil: 'domcontentloaded' });
        }
        const answer = await page.evaluate(async ({ url, body }) => {
          const r = await fetch(url, {
            method: 'POST',
            credentials: 'include',
            headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
          });
          const text = await r.text();
          let json = null;
          try { json = JSON.parse(text); } catch (e) { json = null; }
          return { status: r.status, json, text: text.slice(0, 300) };
        }, req);
        const ok = answer.status >= 200 && answer.status < 300;
        results.push({
          number: item.number,
          status: answer.status,
          ok,
          url: ok ? address(item, answer.json) : null,
          reason: ok ? null : `Substack answered ${answer.status}: ${answer.text}`,
        });
      } catch (e) {
        results.push({ number: item.number, status: null, ok: false, reason: String(e).slice(0, 300) });
      }
      // A reader's pace between two of them, never a burst.
      await new Promise((r) => setTimeout(r, 3000 + Math.random() * 4000));
    }
  } finally {
    await context.close();
  }
  process.stdout.write(JSON.stringify(results));
}

main().catch((e) => {
  process.stderr.write(String(e));
  process.exit(1);
});
