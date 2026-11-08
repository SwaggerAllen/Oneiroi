import { useState } from 'react';
import type { Block, CorrespondenceMessage, Reply } from '../../api/types';
import { Card } from '../../components/Card';
import { type GateActions, Message, OwnReply } from '../inbox/NeedsYou';
import { type Entry, threads } from '../inbox/threads';

// Correspondence, its own page (the witness, 2026-11-08, through Lily's
// letter #330): filter first, by participant and by conversation, with
// no phrase needed ("everything involving Jack"); time order the spine;
// each entry says whose it is, so "which message is hers" is read, not
// opened.
export function CorrespondencePage({
  residentName,
  messages,
  replies = [],
  blocks = [],
  onBlock,
}: {
  residentName: string;
  messages: CorrespondenceMessage[];
  replies?: Reply[];
  blocks?: Block[];
  onBlock?: GateActions['onBlock'];
}) {
  const [who, setWho] = useState('');
  const [thread, setThread] = useState('');
  const [newestFirst, setNewestFirst] = useState(false);
  const all = threads(messages, replies);
  const people = [...new Set(all.map((t) => t.with))].sort((a, b) => a.localeCompare(b));
  const blocked = new Set(blocks.map((b) => `${b.platform}:${b.identity}`));

  const entries = all
    .filter((t) => (who === '' || t.with === who) && (thread === '' || t.key === thread))
    .flatMap((t) => t.entries.map((e) => ({ thread: t, entry: e })))
    .sort((a, b) => (newestFirst ? b.entry.at.localeCompare(a.entry.at) : a.entry.at.localeCompare(b.entry.at)));

  const one = ({ entry: e, thread: t }: { entry: Entry; thread: (typeof all)[number] }) => (
    <div key={e.kind === 'message' ? `m${e.message.number}` : `r${e.reply.number}`} style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <p style={{ margin: 0, fontSize: 13, fontWeight: 600, color: e.kind === 'reply' ? 'var(--witness)' : 'var(--ink)' }}>
        {e.kind === 'reply' ? `${residentName}’s` : `From ${t.with}`} · with {t.with}
      </p>
      <ol style={{ margin: 0, padding: 0, listStyle: 'none' }}>
        {e.kind === 'message' ? (
          <Message message={e.message} blocked={blocked.has(`${e.message.platform}:${e.message.sender}`)} onBlock={onBlock} />
        ) : (
          <OwnReply residentName={residentName} reply={e.reply} />
        )}
      </ol>
    </div>
  );

  const select = { minHeight: 'var(--control-h)', fontSize: 15, maxWidth: '100%' } as const;
  return (
    <>
      <Card title="Filter">
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
          <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13, minWidth: 0 }}>
            Participant
            <select aria-label="Participant" value={who} onChange={(e) => setWho(e.target.value)} style={select}>
              <option value="">Everyone</option>
              {people.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </select>
          </label>
          <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13, minWidth: 0 }}>
            Conversation
            <select aria-label="Conversation" value={thread} onChange={(e) => setThread(e.target.value)} style={select}>
              <option value="">Every conversation</option>
              {all
                .filter((t) => who === '' || t.with === who)
                .map((t) => {
                  const first = t.entries.find((e) => e.kind === 'message');
                  const subject = first?.kind === 'message' ? first.message.subject : null;
                  return (
                    <option key={t.key} value={t.key}>
                      With {t.with}
                      {subject ? `: ${subject}` : ''} ({t.entries.length})
                    </option>
                  );
                })}
            </select>
          </label>
          <label style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 15 }}>
            <input type="checkbox" checked={newestFirst} onChange={(e) => setNewestFirst(e.target.checked)} />
            Newest first
          </label>
        </div>
      </Card>
      <Card title={`${entries.length} ${entries.length === 1 ? 'message' : 'messages'}`}>
        {entries.length === 0 ? (
          <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>None{who || thread ? ' matches' : ' yet'}.</p>
        ) : (
          <div aria-label="Messages" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
            {entries.map(one)}
          </div>
        )}
      </Card>
    </>
  );
}
