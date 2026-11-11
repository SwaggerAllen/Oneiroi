import { useEffect, useState } from 'react';
import { ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import type { Live } from '../live/live';
import { useShell } from '../state/store';
import { Mail } from '../inbox/Mail';
import { Chat } from './Chat';
import * as css from './chatTab.css';
import { documentPath, type Citation } from './cite';
import { Peek } from './Peek';
import { Sessions } from './Sessions';

/** The Chat tab (ui-structures.md D): Conversation | Sessions | Mail, and the peek. */
export function ChatTab({ residentId, residentName, live, path }: { residentId: string; residentName: string; live: Live; path: string }) {
  const [view, setView] = useState<'conversation' | 'sessions' | 'mail'>(() => (path === 'mail' ? 'mail' : 'conversation'));
  const [peek, setPeek] = useState<Citation | null>(null);
  const setTab = useShell((s) => s.setTab);
  const push = useShell((s) => s.push);
  // `turn/<session>/<turn>` (from search): the conversation, at that turn.
  const [, session, turn] = path.startsWith('turn/') ? path.split('/') : [];
  const jump = session && turn ? { session, turn } : null;
  useEffect(() => {
    if (path.startsWith('turn/')) setView('conversation');
    if (path === 'mail') setView('mail');
  }, [path]);

  const openFully = (c: Citation) => {
    setPeek(null);
    setTab('records');
    const path = documentPath(c);
    push(path ? `doc/${path}` : `cite/${c.kind}/${c.ref}`);
  };

  return (
    <div className={css.tab}>
      <ToggleButtonGroup
        aria-label="Chat view"
        selectionMode="single"
        disallowEmptySelection
        selectedKeys={[view]}
        onSelectionChange={(keys) => setView([...keys][0] as 'conversation' | 'sessions' | 'mail')}
        className={css.switcher}
      >
        <ToggleButton id="conversation" className={css.option}>
          Conversation
        </ToggleButton>
        <ToggleButton id="sessions" className={css.option}>
          Sessions
        </ToggleButton>
        <ToggleButton id="mail" className={css.option}>
          Mail
        </ToggleButton>
      </ToggleButtonGroup>
      <div className={css.body}>
        {/* Both stay mounted: the conversation keeps its place and its draft. */}
        <div className={css.pane} hidden={view !== 'conversation'}>
          <Chat residentId={residentId} residentName={residentName} live={live} onCite={setPeek} jump={jump} />
          <Peek residentId={residentId} citation={peek} onClose={() => setPeek(null)} onOpenFully={openFully} onCite={setPeek} />
        </div>
        <div className={css.pane} hidden={view !== 'sessions'}>
          <Sessions residentId={residentId} onConversation={() => setView('conversation')} />
        </div>
        <div className={css.pane} hidden={view !== 'mail'}>
          {view === 'mail' && <Mail />}
        </div>
      </div>
    </div>
  );
}
