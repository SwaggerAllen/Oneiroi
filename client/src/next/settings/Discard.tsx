import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { api } from "../../api/client";
import { Card, Field } from "./common";
import * as css from "./settings.css";

/**
 * Deleting a resident before their first turn (agathos-daimon#49;
 * screens/next-settings.md): the witness's, with a note, confirmed once in
 * place. Until the first conversation with you, trials and gift reads
 * included, they can go; after it, never. The log keeps a tombstone.
 */
export function Discard({
  id,
  name,
  onGone,
}: {
  id: string;
  name: string;
  onGone?: () => void;
}) {
  const queries = useQueryClient();
  const [note, setNote] = useState("");
  const [sure, setSure] = useState(false);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const go = async () => {
    setBusy(true);
    setSaid(null);
    try {
      await api.discardResident(id, note.trim());
      await queries.invalidateQueries({ queryKey: ["residents"] });
      onGone?.();
      setSaid(`${name} is deleted.`);
    } catch (e) {
      setSaid((e as Error).message);
      setSure(false);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Card title={`Delete ${name}`}>
      <p className={css.text}>
        {name} has not had a first conversation with you, so they can still be
        deleted: their files, trials and settings go, and their slug is free
        again. The record keeps a line saying you deleted them, when and why.
        After a first conversation this is gone for good.
      </p>
      <form
        aria-label={`Delete ${name}`}
        className={css.row}
        onSubmit={(e) => {
          e.preventDefault();
          if (!sure) setSure(true);
          else void go();
        }}
      >
        <Field
          label="Why delete them"
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
        <button
          type="submit"
          className={css.quiet}
          disabled={busy || !note.trim()}
        >
          {sure ? `Delete ${name} for good` : "Delete"}
        </button>
      </form>
      {said && <p className={css.note}>{said}</p>}
    </Card>
  );
}
