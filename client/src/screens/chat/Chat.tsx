import { useState } from 'react';
import type { Injection, Message } from '../../api/types';
import { ActorChip } from '../../components/ActorChip';
import { Button } from '../../components/Button';
import { EmptyState } from '../../components/EmptyState';
import { RefusalBlock } from '../../components/RefusalBlock';
import { TopBar } from '../../components/TopBar';

export interface ChatProps {
  residentName: string;
  messages: Message[];
  // The reply being streamed, by turn ref, until the turn lands.
  streaming?: { turnRef: string; text: string } | null;
  // What each reply drew on, by turn ref, once opened.
  injections?: Record<string, Injection[]>;
  drewOn?: Record<string, number>;
  sending?: boolean;
  onSend: (text: string) => void;
  onInspect?: (turnRef: string) => void;
  onProposeBookmark?: (message: Message) => void;
}

// Chat is home (spec §10): the main conversation as a transcript, refusals
// in the resident's words, "drew on N things" per reply, the composer.
// Replies are not regenerated and sent messages are not edited.
export function Chat({
  residentName,
  messages,
  streaming = null,
  injections = {},
  drewOn = {},
  sending = false,
  onSend,
  onInspect,
  onProposeBookmark,
}: ChatProps) {
  const [draft, setDraft] = useState('');
  const submit = () => {
    const text = draft.trim();
    if (!text || sending) return;
    onSend(text);
    setDraft('');
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title={residentName} line="Main conversation" />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        {messages.length === 0 && !streaming ? (
          <EmptyState text={`Say something to ${residentName}.`} />
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
            background: mine ? 'var(--steward-tint)' : 'transparent',
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
        <ul
          style={{
            margin: 0,
            padding: 'var(--space-3)',
            listStyle: 'none',
            background: 'var(--surface-sunken)',
            borderRadius: 'var(--radius-md)',
            fontSize: 13,
            lineHeight: '18px',
            display: 'flex',
            flexDirection: 'column',
            gap: 'var(--space-1)',
          }}
        >
          {injections.map((inj) => (
            <li key={inj.position}>
              <strong>{inj.label}</strong>, about {inj.tokens} tokens: {inj.reason}
              {inj.text ? (
                <pre style={{ margin: 'var(--space-1) 0 0', whiteSpace: 'pre-wrap', fontFamily: 'var(--font-mono)', fontSize: 12 }}>
                  {inj.text}
                </pre>
              ) : null}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
