import { useState, type ReactNode } from 'react';
import type { ContextPreview, Injection, Message } from '../../api/types';
import { ActorChip } from '../../components/ActorChip';
import { Button } from '../../components/Button';
import { EmptyState } from '../../components/EmptyState';
import { RefusalBlock } from '../../components/RefusalBlock';
import { TopBar } from '../../components/TopBar';

export interface ChatProps {
  residentName: string;
  // The conversation shown, as the server named it (kumbukumbu #40);
  // absent, the Oneiroi chat. One that is not writable is read here and
  // answered where it happens, so it has no composer and no preview.
  conversation?: { title: string; writable: boolean };
  // The list of conversations, rendered under the top bar.
  conversations?: ReactNode;
  messages: Message[];
  // The reply being streamed, by turn ref, until the turn lands.
  streaming?: { turnRef: string; text: string } | null;
  // What each reply drew on, by turn ref, once opened.
  injections?: Record<string, Injection[]>;
  drewOn?: Record<string, number>;
  sending?: boolean;
  // What the next turn would be given, as the server assembled and
  // worded it (brain #41); null while closed.
  preview?: ContextPreview | null;
  onSend: (text: string) => void;
  // Opens the preview with the draft as it stands, or closes it.
  onPreview?: (draft: string) => void;
  onInspect?: (turnRef: string) => void;
  onProposeBookmark?: (message: Message) => void;
}

// Chat is home (spec §10): the main conversation as a transcript, refusals
// in the resident's words, "drew on N things" per reply (what that turn
// drew on), the preview of what the next turn would be given, the
// composer. Replies are not regenerated and sent messages are not edited.
// The same screen reads another conversation (a Claude Code one) when
// the server says it is not writable: the transcript and the inspector,
// with no composer and no preview (kumbukumbu #40).
export function Chat({
  residentName,
  conversation,
  conversations = null,
  messages,
  streaming = null,
  injections = {},
  drewOn = {},
  sending = false,
  preview = null,
  onSend,
  onPreview,
  onInspect,
  onProposeBookmark,
}: ChatProps) {
  const [draft, setDraft] = useState('');
  const writable = conversation?.writable ?? true;
  // Which model answered, as the server recorded it on the reply: the
  // pin is otherwise invisible here, and a pin that did not take was
  // only found by asking the resident who she was.
  const lastModel = [...messages].reverse().find((m) => m.role === 'assistant')?.actor.model ?? null;
  const submit = () => {
    const text = draft.trim();
    if (!text || sending) return;
    onSend(text);
    setDraft('');
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar
        title={residentName}
        line={
          !writable
            ? `${conversation?.title} · read here, answered there`
            : lastModel
              ? `Main conversation · last reply on ${lastModel}`
              : 'Main conversation'
        }
      />
      {conversations}
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        {messages.length === 0 && !streaming ? (
          <EmptyState text={writable ? `Say something to ${residentName}.` : 'Nothing captured here yet.'} />
        ) : null}
        {messages.map((m) => (
          <Reply
            key={`${m.turn_ref}-${m.sent_at}-${m.role}-${m.content.slice(0, 16)}`}
            message={m}
            residentName={residentName}
            drewOn={drewOn[m.turn_ref]}
            injections={injections[m.turn_ref]}
            onInspect={onInspect}
            onProposeBookmark={onProposeBookmark}
          />
        ))}
        {streaming ? (
          <p
            aria-live="polite"
            style={{ margin: 0, fontFamily: 'var(--font-serif)', fontSize: 17, lineHeight: '26px', color: 'var(--ink-muted)' }}
          >
            {streaming.text}
          </p>
        ) : null}
      </main>
      {!writable ? (
        <p
          role="note"
          style={{
            margin: 0,
            padding: 'var(--space-3) var(--space-4)',
            borderTop: '1px solid var(--hairline)',
            color: 'var(--ink-muted)',
            fontSize: 14,
          }}
        >
          {`A conversation of its own, separate from your chat with ${residentName}. You reply to ${residentName} there, not here.`}
        </p>
      ) : null}
      {writable && onPreview ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', padding: '0 var(--space-4) var(--space-3)' }}>
          <div>
            <Button variant="quiet" onClick={() => onPreview(draft)}>
              {preview ? 'Close the preview' : `What ${residentName} will see next`}
            </Button>
          </div>
          {preview ? <Preview preview={preview} /> : null}
        </div>
      ) : null}
      {writable ? (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            submit();
          }}
          style={{
            display: 'flex',
            gap: 'var(--space-2)',
            padding: 'var(--space-3) var(--space-4)',
            borderTop: '1px solid var(--hairline)',
            background: 'var(--surface-raised)',
          }}
        >
          <input
            aria-label="Message"
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            placeholder={`Write to ${residentName}`}
            style={{
              flex: 1,
              minHeight: 'var(--control-h)',
              padding: '0 var(--space-3)',
              borderRadius: 'var(--radius-md)',
              border: '1px solid var(--hairline)',
              background: 'var(--surface)',
              color: 'var(--ink)',
              fontFamily: 'var(--font-sans)',
              fontSize: 15,
            }}
          />
          <Button variant="primary" type="submit" disabled={sending || draft.trim() === ''}>
            Send
          </Button>
        </form>
      ) : null}
    </div>
  );
}

function Reply({
  message,
  residentName,
  drewOn,
  injections,
  onInspect,
  onProposeBookmark,
}: {
  message: Message;
  residentName: string;
  drewOn?: number;
  injections?: Injection[];
  onInspect?: (turnRef: string) => void;
  onProposeBookmark?: (message: Message) => void;
}) {
  const mine = message.role === 'user';
  const system = message.role === 'system';
  const tool = message.role === 'tool';
  if (tool) {
    return (
      <p style={{ margin: 0, fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--ink-faint)' }}>
        {message.content}
      </p>
    );
  }
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', alignItems: mine ? 'flex-end' : 'stretch' }}>
      <ActorChip actor={message.actor} name={mine ? 'you' : system ? 'Oneiroi' : residentName} />
      {message.refusal ? (
        <RefusalBlock text={message.content} />
      ) : (
        <p
          style={{
            margin: 0,
            padding: mine ? 'var(--space-2) var(--space-3)' : 0,
            borderRadius: 'var(--radius-lg)',
            background: mine ? 'var(--witness-tint)' : 'transparent',
            fontFamily: mine || system ? 'var(--font-sans)' : 'var(--font-serif)',
            fontSize: mine || system ? 15 : 17,
            lineHeight: mine || system ? '22px' : '26px',
            color: system ? 'var(--ink-muted)' : 'var(--ink)',
            maxWidth: 'var(--measure)',
            whiteSpace: 'pre-wrap',
          }}
        >
          {message.content}
        </p>
      )}
      {message.role === 'assistant' ? (
        <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
          {drewOn !== undefined && onInspect ? (
            <Button variant="quiet" onClick={() => onInspect(message.turn_ref)}>
              drew on {drewOn} things
            </Button>
          ) : null}
          {onProposeBookmark ? (
            <Button variant="quiet" onClick={() => onProposeBookmark(message)}>
              Propose a bookmark
            </Button>
          ) : null}
        </div>
      ) : null}
      {injections && message.role === 'assistant' ? (
        <div style={panel}>
          <Sections
            name="What this reply drew on"
            sections={injections.map((inj) => ({ key: String(inj.position), label: inj.label, tokens: inj.tokens, reason: inj.reason, text: inj.text, note: null }))}
          />
        </div>
      ) : null}
    </div>
  );
}

// The next turn's sections in the order the server assembled them; each
// shows its words where the server sent them and its note otherwise. The
// client decides nothing here: which sections exist, their order, their
// counts and what is withheld are all the server's.
function Preview({ preview }: { preview: ContextPreview }) {
  return (
    <section aria-label="The next turn, previewed" style={panel}>
      <p style={{ margin: 0, color: 'var(--ink-muted)' }}>{preview.description}</p>
      <Sections
        name="What the next turn is given"
        sections={preview.sections.map((section, i) => ({
          key: `${section.label}-${i}`,
          label: section.label,
          tokens: section.tokens,
          reason: section.reason,
          text: section.text,
          note: section.note,
        }))}
      />
    </section>
  );
}

const panel = {
  padding: 'var(--space-3)',
  background: 'var(--surface-sunken)',
  borderRadius: 'var(--radius-md)',
  fontSize: 13,
  lineHeight: '18px',
  display: 'flex',
  flexDirection: 'column' as const,
  gap: 'var(--space-2)',
  overflowWrap: 'anywhere' as const,
};

interface SectionRow {
  key: string;
  label: string;
  tokens: number;
  reason: string;
  text: string | null;
  note: string | null;
}

// The overview first, every section closed: its label and size on one
// line, so the whole assembly reads at a glance on a phone. A section
// opens to its reason, its words where the server sent them and its
// note. The author asked for it this way after the first preview showed
// every section's whole text at once ("minimized by default, with
// minimizeable sections so I can see an overview and then dive down").
// Open all and Close all are the two ways down and back at once.
function Sections({ name, sections }: { name: string; sections: SectionRow[] }) {
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const all = sections.length > 0 && sections.every((s) => open[s.key]);
  return (
    <>
      {sections.length > 1 ? (
        <div>
          <Button variant="quiet" onClick={() => setOpen(all ? {} : Object.fromEntries(sections.map((s) => [s.key, true])))}>
            {all ? 'Close all' : 'Open all'}
          </Button>
        </div>
      ) : null}
      <ol aria-label={name} style={{ margin: 0, paddingLeft: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        {sections.map((section) => (
          <li key={section.key}>
            <details
              open={Boolean(open[section.key])}
              onToggle={(event) => {
                const now = (event.currentTarget as HTMLDetailsElement).open;
                setOpen((o) => (Boolean(o[section.key]) === now ? o : { ...o, [section.key]: now }));
              }}
            >
              <summary style={{ cursor: 'pointer' }}>
                <strong>{section.label}</strong> · about {section.tokens} tokens
              </summary>
              <p style={{ margin: 'var(--space-1) 0 0' }}>{section.reason}</p>
              {section.text !== null ? (
                <pre style={{ margin: 'var(--space-1) 0 0', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', fontFamily: 'var(--font-mono)', fontSize: 12 }}>
                  {section.text}
                </pre>
              ) : null}
              {section.note ? <p style={{ margin: 'var(--space-1) 0 0', color: 'var(--ink-faint)' }}>{section.note}</p> : null}
            </details>
          </li>
        ))}
      </ol>
    </>
  );
}
