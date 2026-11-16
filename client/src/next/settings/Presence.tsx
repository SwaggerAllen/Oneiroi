import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type PresenceAccount, type PresenceInteraction, type PresenceState } from '../../api/client';
import { useSubject } from '../state/resident';
import { Card, Field, Said, TextArea } from './common';
import { day, plural, settingsKey } from './logic';
import * as css from './settings.css';
import { useAct } from './useAct';

/**
 * Presence on Substack (xenia#20; screens/next-settings.md): the switch and
 * the handle whose subscriptions it reads, the review of what the resident
 * staged (approve, revise or pass, a comment on any), what went out, and
 * the follow list with its mask. Every interaction goes out under the
 * Allen Strut name, after this review and never before.
 */
export function Presence() {
  const { id } = useSubject();
  const key = settingsKey(id, 'presence');
  const state = useQuery({ queryKey: key, queryFn: () => api.presence(id) });
  if (state.isError) return <p className={css.refused}>Presence could not be read.</p>;
  if (!state.data) return <p className={css.note}>Reading presence…</p>;
  return (
    <>
      <Switch state={state.data} />
      <Review state={state.data} />
      <Sent state={state.data} />
      <Follows state={state.data} />
    </>
  );
}

function Switch({ state }: { state: PresenceState }) {
  const { id, name } = useSubject();
  const s = state.settings;
  const [handle, setHandle] = useState(s.handle ?? '');
  const act = useAct();
  const pass = state.passes[0];
  return (
    <Card title="Presence">
      <p className={css.text}>
        {s.enabled
          ? `On: each night ${name} reads a random handful of the accounts @${s.handle} follows, in turn, and stages what earned a like, a comment or a restack, for you to review.`
          : `Off: nothing is read and nothing is staged.`}
      </p>
      {pass && (
        <p className={css.meta}>
          Last pass {pass.day}: {plural(pass.accounts.length, 'account')}, {plural(pass.pool, 'item')} in the pool, {pass.ranked} read off the top and {pass.serendipity} from below,
          up to {plural(pass.cap, 'interaction')}.
        </p>
      )}
      <p className={css.warn}>
        Before the first one goes out: what does the StrutCo About page say about Allen Strut? If it declares the persona, a reaction from it is honest by construction; if it reads
        as a person's account, every one blurs the line the community and Substack watch.
      </p>
      <form
        aria-label="Presence"
        className={css.row}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(() => api.setPresence(id, !s.enabled, handle).then(() => (s.enabled ? 'Turned off.' : 'Turned on.')));
        }}
      >
        <Field label="Substack handle" autoComplete="off" value={handle} onChange={(e) => setHandle(e.target.value)} />
        <button type="submit" className={s.enabled ? css.secondary : css.primary} disabled={handle.trim() === '' || act.busy}>
          {s.enabled ? 'Turn off' : 'Turn on'}
        </button>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

const WORDS: Record<PresenceInteraction['kind'], string> = { like: 'A like', comment: 'A comment', restack: 'A restack' };

function Review({ state }: { state: PresenceState }) {
  const { name } = useSubject();
  const waiting = state.interactions.filter((i) => i.state === 'staged');
  const revising = state.interactions.filter((i) => i.state === 'revise');
  return (
    <Card title="To review">
      {waiting.length === 0 && <p className={css.note}>Nothing waiting on you.</p>}
      {waiting.length > 0 && (
        <ul className={css.list} aria-label="Waiting on you">
          {waiting.map((i) => (
            <Staged key={i.number} interaction={i} />
          ))}
        </ul>
      )}
      {revising.length > 0 && (
        <p className={css.meta}>
          Sent back for revision: {revising.map((i) => `#${i.number}`).join(', ')}. {name} revises them on the next pass.
        </p>
      )}
    </Card>
  );
}

function Staged({ interaction: i }: { interaction: PresenceInteraction }) {
  const { id } = useSubject();
  const [comment, setComment] = useState('');
  const act = useAct();
  const r = i.read;
  const decide = (decision: 'approve' | 'revise' | 'pass') =>
    void act.run(
      () =>
        api.decideInteraction(id, i.number, decision, comment.trim() || null).then(() => {
          setComment('');
          return decision === 'approve' ? 'Approved: it goes out at a random time in the next few hours.' : decision === 'revise' ? 'Sent back for revision.' : 'Passed over.';
        }),
      settingsKey(id, 'presence'),
    );
  return (
    <li className={css.item} aria-label={`Interaction ${i.number}`}>
      <p className={css.meta}>
        #{i.number} · {WORDS[i.kind]} on {r?.title ? `“${r.title}”` : 'a note'} from {i.account}
        {i.supersedes ? ` · revises #${i.supersedes}` : ''}
      </p>
      {i.text && <p className={css.voice}>{i.text}</p>}
      {r && (
        <p className={css.note}>
          <a className={css.link} href={r.url} target="_blank" rel="noreferrer">
            {r.url}
          </a>{' '}
          · {r.likes} likes, {r.comments} comments, {r.restacks} restacks · {r.cut === 'ranked' ? 'read off the top' : 'read from below'}
          {r.excerpt ? ` · ${r.excerpt}` : ''}
        </p>
      )}
      <TextArea label="Your comment (needed to ask a revision)" value={comment} onChange={(e) => setComment(e.target.value)} />
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={act.busy} onClick={() => decide('approve')}>
          Approve
        </button>
        <button type="button" className={css.secondary} disabled={act.busy || comment.trim() === ''} onClick={() => decide('revise')}>
          Ask for a revision
        </button>
        <button type="button" className={css.quiet} disabled={act.busy} onClick={() => decide('pass')}>
          Hard pass
        </button>
      </div>
      <Said said={act.said} />
    </li>
  );
}

const STATE_WORDS: Partial<Record<PresenceInteraction['state'], (i: PresenceInteraction) => string>> = {
  approved: (i) => `approved, goes out ${i.release_at ? `after ${new Date(i.release_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}` : 'soon'}`,
  sent: (i) => `sent ${day(i.sent_at)}`,
  failed: (i) => `failed: ${i.reason ?? 'no reason given'}`,
  passed: () => 'passed over',
};

function Sent({ state }: { state: PresenceState }) {
  const done = state.interactions.filter((i) => i.state in STATE_WORDS).slice(0, 20);
  if (done.length === 0) return null;
  return (
    <Card title="Decided">
      <ul className={css.list} aria-label="Decided interactions">
        {done.map((i) => (
          <li key={i.number} className={css.line}>
            #{i.number} {WORDS[i.kind].toLowerCase()} on {i.read?.title ? `“${i.read.title}”` : 'a note'} ({i.account}): {STATE_WORDS[i.state]?.(i)}
            {i.comment ? ` · your comment: ${i.comment}` : ''}
            {i.url && i.state === 'sent' && (
              <>
                {' · '}
                <a className={css.link} href={i.url} target="_blank" rel="noreferrer">
                  where it is
                </a>
              </>
            )}
          </li>
        ))}
      </ul>
    </Card>
  );
}

function Follows({ state }: { state: PresenceState }) {
  const { id } = useSubject();
  const act = useAct();
  const followed = state.accounts.filter((a) => a.followed);
  const masked = followed.filter((a) => a.excluded).length;
  const s = state.settings;
  return (
    <Card title="The follow list">
      <p className={css.text}>
        {s.follows_at
          ? `${plural(followed.length, 'account')} from @${s.handle}'s public subscriptions, fetched ${day(s.follows_at)} and matched to the ${s.visible ?? '?'} the profile shows; ${masked} masked. The rotation reads the rest in turn${s.cursor ? `, next after ${s.cursor}` : ''}.`
          : 'Not fetched yet. It is fetched before each pass, and here on asking.'}
      </p>
      <p className={css.note}>A mask is not an unfollow: the follow stays, and the rotation passes over it. Each one is dated, with its reason, so it can be read back later.</p>
      <div className={css.row}>
        <button
          type="button"
          className={css.secondary}
          disabled={act.busy || !s.handle}
          onClick={() => void act.run(() => api.refreshFollows(id).then((r) => `Fetched ${plural(r.accounts, 'account')}.`), settingsKey(id, 'presence'))}
        >
          Fetch the list now
        </button>
      </div>
      <Said said={act.said} />
      {followed.length > 0 && (
        <ul className={css.list} aria-label="Followed accounts">
          {followed.map((a) => (
            <Account key={a.key} account={a} />
          ))}
        </ul>
      )}
    </Card>
  );
}

function Account({ account: a }: { account: PresenceAccount }) {
  const { id } = useSubject();
  const [reason, setReason] = useState('');
  const act = useAct();
  const run = (work: () => Promise<void>, said: string) =>
    void act.run(
      () =>
        work().then(() => {
          setReason('');
          return said;
        }),
      settingsKey(id, 'presence'),
    );
  return (
    <li className={css.item}>
      <p className={css.meta}>
        <a className={css.link} href={a.host} target="_blank" rel="noreferrer">
          {a.name ?? a.key}
        </a>{' '}
        · {a.excluded ? `masked ${day(a.excluded_at)}: ${a.reason}` : a.last_sampled_at ? `last read ${day(a.last_sampled_at)}` : 'not read yet'}
      </p>
      <form
        className={css.row}
        aria-label={`Mask ${a.key}`}
        onSubmit={(e) => {
          e.preventDefault();
          if (!reason.trim()) return;
          if (a.excluded) run(() => api.includeAccount(id, a.key, reason.trim()), 'Back in the rotation.');
          else run(() => api.excludeAccount(id, a.key, reason.trim()), 'Masked.');
        }}
      >
        <Field label={a.excluded ? 'Why it comes back' : 'Why mask it (one line)'} value={reason} onChange={(e) => setReason(e.target.value)} />
        <button type="submit" className={css.quiet} disabled={reason.trim() === '' || act.busy}>
          {a.excluded ? 'Unmask' : 'Mask'}
        </button>
      </form>
      <Said said={act.said} />
    </li>
  );
}
