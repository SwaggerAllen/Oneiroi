import { useState } from 'react';
import type { Domain } from '../../api/types';
import * as css from './chat.css';
import { chipLabel } from './domains';

/**
 * The domain the next message goes in (P23-R1, kumbukumbu#72), above the
 * composer: the conversation's current one unless picked otherwise, so
 * an ordinary message needs no click and a change of subject needs one.
 * What is picked holds for the message sent next, and the server carries
 * it to every message after until another is named. The choices are the
 * domains the agreement declares and the common room, never free text
 * (kumbukumbu#90): a new domain is declared in the agreement first.
 */
export function DomainChip({
  now,
  known,
  picked,
  onPick,
}: {
  now: Domain | null;
  known: string[];
  picked: string | null | undefined;
  onPick: (domain: string | null | undefined) => void;
}) {
  const [open, setOpen] = useState(false);
  const label = chipLabel(picked, now);
  const named = label !== 'common room';
  const choose = (domain: string | null) => {
    // Picking what the conversation is already in is no change.
    onPick(domain === (now?.slug ?? null) ? undefined : domain);
    setOpen(false);
  };

  return (
    <div className={css.domainBar}>
      <span>In</span>
      <button
        type="button"
        className={named ? `${css.domainChip} ${css.domainChipNamed}` : css.domainChip}
        aria-expanded={open}
        aria-label={`Domain of the next message: ${label}. Change it`}
        onClick={() => setOpen((o) => !o)}
      >
        {label}
        {picked !== undefined ? ' · next message' : ''}
      </button>
      {open && (
        <div className={css.domainPicker} role="group" aria-label="Choose a domain">
          {known.map((slug) => (
            <button key={slug} type="button" className={css.domainOption} aria-pressed={label === slug} onClick={() => choose(slug)}>
              {slug}
            </button>
          ))}
          <button type="button" className={css.domainOption} aria-pressed={label === 'common room'} onClick={() => choose(null)}>
            common room
          </button>
          {known.length === 0 && <span className={css.domainOption}>no domains declared in the agreement yet</span>}
        </div>
      )}
    </div>
  );
}
