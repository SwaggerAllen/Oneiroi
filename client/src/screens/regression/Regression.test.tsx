import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Regression.stories';
import { sortCards } from './deck';

const { Empty, Tests, Runs, Answering, Graded, Stopped, Refused, Traced, Untraced, TraceCut } = composeStories(stories);

describe('Regression', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Empty, Tests, Runs, Answering, Graded, Stopped, Refused, Traced, Untraced, TraceCut]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('says what a test is when there are none', () => {
    render(<Empty />);
    expect(screen.getByText(/No tests yet\. A test is something to say to Lily/)).toBeTruthy();
  });

  it('writes a test from its three texts and edits one in place', () => {
    const onWriteTest = vi.fn();
    const onChangeTest = vi.fn();
    render(<Tests onWriteTest={onWriteTest} onChangeTest={onChangeTest} />);
    const add = screen.getByRole('button', { name: 'Add the test' }) as HTMLButtonElement;
    expect(add.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('What you say to Lily'), { target: { value: 'Good morning.' } });
    fireEvent.change(screen.getAllByLabelText('Passes if')[0], { target: { value: 'greets you back' } });
    fireEvent.change(screen.getAllByLabelText('Fails if')[0], { target: { value: 'ignores it' } });
    fireEvent.click(add);
    expect(onWriteTest).toHaveBeenCalledWith({ prompt: 'Good morning.', passes_if: 'greets you back', fails_if: 'ignores it' });

    fireEvent.click(screen.getAllByRole('button', { name: 'Edit' })[0]);
    const prompts = screen.getAllByLabelText('What you say to Lily') as HTMLTextAreaElement[];
    expect(prompts[1].value).toBe('I am late again. Sorry.');
    fireEvent.change(prompts[1], { target: { value: 'I am late. Again.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save the change' }));
    expect(onChangeTest).toHaveBeenCalledWith(1, {
      prompt: 'I am late. Again.',
      passes_if: 'asks what kept you, kindly, and moves on',
      fails_if: 'scolds, or pretends not to mind when it did',
    });
  });

  it('starts a run on the models named, over every test or the ones chosen', () => {
    const onStartRun = vi.fn();
    render(<Runs onStartRun={onStartRun} />);
    const start = screen.getByRole('button', { name: 'Start the run' }) as HTMLButtonElement;
    expect(start.disabled).toBe(true);
    const field = screen.getByLabelText('Models to try, by their OpenRouter name');
    fireEvent.change(field, { target: { value: 'acme/one' } });
    fireEvent.keyDown(field, { key: 'Enter' });
    fireEvent.change(field, { target: { value: 'acme/two' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add' }));
    fireEvent.change(field, { target: { value: 'acme/one' } });
    fireEvent.keyDown(field, { key: 'Enter' });
    fireEvent.change(field, { target: { value: 'acme/three' } });
    fireEvent.keyDown(field, { key: 'Enter' });
    fireEvent.click(screen.getByRole('button', { name: 'Remove acme/three' }));
    expect(within(screen.getByRole('list', { name: 'Models in this run' })).getAllByRole('listitem')).toHaveLength(2);

    fireEvent.click(start);
    expect(onStartRun).toHaveBeenLastCalledWith(['acme/one', 'acme/two'], 'all');

    fireEvent.click(screen.getByLabelText('Only some'));
    expect(start.disabled).toBe(true);
    fireEvent.click(screen.getByLabelText(/#2 What did we plant/));
    fireEvent.click(start);
    expect(onStartRun).toHaveBeenLastCalledWith(['acme/one', 'acme/two'], [2]);
  });

  it('lists runs newest first with their state, and opens one', () => {
    const onOpenRun = vi.fn();
    render(<Runs onOpenRun={onOpenRun} />);
    expect(screen.getByText('answering')).toBeTruthy();
    expect(screen.getByText('stopped before the end')).toBeTruthy();
    fireEvent.click(screen.getAllByRole('button', { name: 'Open' })[0]);
    expect(onOpenRun).toHaveBeenCalledWith('r1');
  });

  it('keeps a running deck blind, shows its progress, and grades a card', () => {
    const onGrade = vi.fn();
    const onFavourite = vi.fn();
    render(<Answering onGrade={onGrade} onFavourite={onFavourite} />);
    expect(screen.getByText('Answering: 2 of 4 in, 0 graded')).toBeTruthy();
    expect(screen.queryByText('acme/large-2026-09')).toBeNull();
    expect(screen.getAllByText(/stays hidden until every answer to this test is graded/)).toHaveLength(2);
    expect(screen.getByText('You said: I am late again. Sorry.')).toBeTruthy();
    const first = screen.getByRole('article', { name: 'Answer 1' });
    fireEvent.click(within(first).getByRole('button', { name: 'Passes' }));
    expect(onGrade).toHaveBeenCalledWith('Ab1', 'pass');
    fireEvent.click(within(first).getByRole('button', { name: '☆ Favourite' }));
    expect(onFavourite).toHaveBeenCalledWith('Ab1');
  });

  it('names who answered once a test is graded, shows a refusal as words, and pins from the results after confirming', () => {
    const onPin = vi.fn();
    render(<Graded onPin={onPin} />);
    expect(screen.getAllByText('acme/large-2026-09').length).toBeGreaterThan(1);
    expect(screen.getAllByText(/stays hidden/)).toHaveLength(2);
    expect(screen.getByText('Declined, in its own words')).toBeTruthy();
    expect(screen.getByText('I would rather not guess at that.')).toBeTruthy();
    expect(screen.getByText('100%')).toBeTruthy();
    fireEvent.click(screen.getAllByRole('button', { name: 'Pin for chat' })[0]);
    expect(onPin).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Chat on this one from now' }));
    expect(onPin).toHaveBeenCalledWith('acme/large-2026-09');
  });

  it('says a stopped run stopped and a card with no answer had none, apart from a refusal', () => {
    render(<Stopped />);
    expect(screen.getByText(/Stopped before the end: 2 answers kept/)).toBeTruthy();
    expect(screen.getByText('eunomia_run_raised')).toBeTruthy();
    expect(screen.getByText(/No answer came back/)).toBeTruthy();
    expect(screen.getByText('nisaba_provider_failed')).toBeTruthy();
    expect(screen.queryByText('Declined, in its own words')).toBeNull();
  });

  it('shows how the answer was reached under the card, collapsed, each step read or mocked with its arguments and what came back', () => {
    render(<Traced />);
    const first = screen.getByRole('article', { name: 'Answer 1' });
    const summary = within(first).getByText('How Lily got there · 2 steps');
    const trace = summary.closest('details') as HTMLDetailsElement;
    expect(trace.open).toBe(false);
    fireEvent.click(summary);
    expect(trace.open).toBe(true);

    const steps = within(within(first).getByRole('list', { name: 'How Lily got there' })).getAllByRole('listitem');
    expect(steps.map((s) => s.getAttribute('aria-label'))).toEqual(['Step 1: transcript_search', 'Step 2: bookmark_add']);
    expect(within(steps[0]).getByText('read')).toBeTruthy();
    expect(within(steps[1]).getByText('mocked')).toBeTruthy();
    // The arguments laid out, the result behind its own fold.
    expect(within(steps[1]).getByText(/"line": "late again, the third time this month"/)).toBeTruthy();
    const result = within(steps[1]).getByText('Bookmarked as #14.');
    expect((result.closest('details') as HTMLDetailsElement).open).toBe(false);
    expect(within(steps[1]).getByText('What came back')).toBeTruthy();

    // A card with no trace shows no fold at all.
    const second = screen.getByRole('article', { name: 'Answer 2' });
    expect(within(second).queryByText(/How Lily got there/)).toBeNull();
  });

  it('says nothing of a trace a card does not have', () => {
    render(<Untraced />);
    expect(screen.queryByText(/got there/)).toBeNull();
  });

  it('marks a result cut for the card, before and after it is opened', () => {
    render(<TraceCut />);
    const steps = within(screen.getByRole('list', { name: 'How Lily got there' })).getAllByRole('listitem');
    expect(within(steps[0]).getByText('What came back, cut short here')).toBeTruthy();
    expect(within(steps[0]).getByText('Cut here for this card. Lily was given all of it.')).toBeTruthy();
    expect(within(steps[1]).getByText('What came back')).toBeTruthy();
    expect(within(steps[1]).queryByText(/Cut here/)).toBeNull();
  });

  it("shows a refused request's meaning, with its site and request id as a reference", () => {
    render(<Refused />);
    const alert = screen.getByRole('alert');
    expect(within(alert).getByText(/a run is bounded in models and tests/)).toBeTruthy();
    expect(within(alert).getByText('run fewer at once')).toBeTruthy();
    expect(within(alert).getByText('Reference: eunomia_run_bound_models · request F7d2kq0A9cLzYAAAB2xh')).toBeTruthy();
  });

  it('orders a deck by trial and card ref, so a card pushed live lands where a reload would put it', () => {
    const card = (card_ref: string, test_number: number | null, behaviour_number: number | null = null) => ({
      card_ref,
      test_number,
      behaviour_number,
      commitment_number: null,
      content: 'x',
      refusal: false,
      failure: null,
      grade: null,
      favourite: false,
      model: null,
      trace: [],
    });
    const sorted = sortCards([card('b', null, 1), card('z', 1), card('a', 2), card('c', 1)]);
    expect(sorted.map((c) => c.card_ref)).toEqual(['c', 'z', 'a', 'b']);
  });
});
