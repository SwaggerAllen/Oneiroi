import { useState } from 'react';
import type { LibraryDocument } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';
import { TopBar } from '../../components/TopBar';
import { humanPath } from './paths';

export interface LibraryProps {
  residentName: string;
  documents: LibraryDocument[];
  // The document open now, with its words, or null.
  open?: { path: string; content: string } | null;
  onOpen?: (path: string) => void;
  onClose?: () => void;
  // Adds a document of yours under human/ (seshat #33).
  onAdd?: (name: string, content: string) => void;
  // Removes a scratch or human document; only those are removable.
  onRemove?: (path: string) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' } as const;

// The order the library reads in: the gifts first, your own, the
// resident's work, and what is meant to go.
const order = ['keepsake', 'human', 'writing', 'design', 'research', 'system', 'wiki', 'posts', 'scratch', 'journal'];

function heading(kind: string, name: string): string {
  switch (kind) {
    case 'keepsake':
      return 'Keepsakes';
    case 'human':
      return 'Yours';
    case 'scratch':
      return 'Scratch (temporary)';
    default:
      return kind === 'writing' ? `${name}'s writing` : kind[0].toUpperCase() + kind.slice(1);
  }
}

// Library (spec §10, screens/library.md): every document the resident's
// library holds, by kind; keepsakes with why each mattered in her words;
// your own documents (human/), which you add and remove and she reads;
// and scratch, removable when its work is done.
export function Library({ residentName, documents, open = null, onOpen, onClose, onAdd, onRemove }: LibraryProps) {
  const kinds = [...new Set(documents.map((d) => d.kind))].sort(
    (a, b) => (order.indexOf(a) + 1 || 99) - (order.indexOf(b) + 1 || 99),
  );
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Library" line={`${documents.length} documents`} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        {open ? (
          <Card title={open.path}>
            <pre style={{ margin: 0, fontFamily: 'var(--font-serif)', fontSize: 15, lineHeight: '23px', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
              {open.content}
            </pre>
            {onClose ? (
              <div>
                <Button onClick={onClose}>Close</Button>
              </div>
            ) : null}
          </Card>
        ) : null}
        {kinds.length === 0 ? <p style={muted}>Nothing in the library yet.</p> : null}
        {kinds.map((kind) => (
          <Card key={kind} title={heading(kind, residentName)}>
            <ul aria-label={heading(kind, residentName)} style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {documents
                .filter((d) => d.kind === kind)
                .map((d) => (
                  <Doc key={d.path} doc={d} residentName={residentName} onOpen={onOpen} onRemove={kind === 'scratch' || kind === 'human' ? onRemove : undefined} />
                ))}
            </ul>
          </Card>
        ))}
        {onAdd ? <AddYours residentName={residentName} onAdd={onAdd} /> : null}
      </main>
    </div>
  );
}

function Doc({ doc, residentName, onOpen, onRemove }: { doc: LibraryDocument; residentName: string; onOpen?: (path: string) => void; onRemove?: (path: string) => void }) {
  const [confirming, setConfirming] = useState(false);
  const name = doc.title ?? doc.path;
  return (
    <li style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
      <span style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 'var(--space-2)' }}>
        {onOpen ? (
          <Button variant="quiet" onClick={() => onOpen(doc.path)}>
            {name}
          </Button>
        ) : (
          <span>{name}</span>
        )}
        {onRemove ? (
          <Button variant="quiet" onClick={() => (confirming ? onRemove(doc.path) : setConfirming(true))} onBlur={() => setConfirming(false)}>
            {confirming ? `Remove ${doc.path}` : 'Remove'}
          </Button>
        ) : null}
      </span>
      <span style={{ fontSize: 13, color: 'var(--ink-muted)' }}>
        {doc.path}
        {doc.missing_at ? ' · missing from the repository' : ''}
        {doc.status ? ` · ${doc.status}` : ''}
      </span>
      {doc.kind === 'keepsake' ? (
        <span style={{ fontSize: 14, fontStyle: 'italic' }}>{doc.note ? `${residentName}: “${doc.note}”` : `${residentName} hasn't said why yet.`}</span>
      ) : null}
    </li>
  );
}

// Your own documents (seshat #33): pasted, or read from a text file.
function AddYours({ residentName, onAdd }: { residentName: string; onAdd: (name: string, content: string) => void }) {
  const [name, setName] = useState('');
  const [content, setContent] = useState('');
  const path = humanPath(name);
  return (
    <Card title="Add a document of yours">
      <p style={muted}>For your own writing that belongs nowhere else. {residentName} can read it; only you can change or remove it.</p>
      <form
        aria-label="Add a document of yours"
        onSubmit={(e) => {
          e.preventDefault();
          if (path && content.trim()) {
            onAdd(path, content);
            setName('');
            setContent('');
          }
        }}
        style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
      >
        <Field label="Name" value={name} onChange={(e) => setName(e.target.value)} placeholder="my-substack-post" />
        <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
          <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Text</span>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={6}
            style={{
              padding: 'var(--space-2) var(--space-3)',
              borderRadius: 'var(--radius-md)',
              border: '1px solid var(--hairline)',
              background: 'var(--surface-raised)',
              color: 'var(--ink)',
              fontFamily: 'var(--font-sans)',
              fontSize: 15,
            }}
          />
        </label>
        <div style={row}>
          <label style={{ fontSize: 13 }}>
            <span style={{ color: 'var(--ink-muted)' }}>Or read a .md or .txt file: </span>
            <input
              type="file"
              accept=".md,.txt,text/markdown,text/plain"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (!file) return;
                void file.text().then((t) => {
                  setContent(t);
                  if (!name) setName(file.name);
                });
              }}
            />
          </label>
          <Button variant="primary" type="submit" disabled={!path || content.trim() === ''}>
            Add {path ?? ''}
          </Button>
        </div>
      </form>
    </Card>
  );
}
