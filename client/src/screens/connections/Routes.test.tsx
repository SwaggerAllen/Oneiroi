import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Routes.stories';

const { Registry } = composeStories(stories);

describe('Routes', () => {
  afterEach(cleanup);

  // xenia#19: a revoked profile's routes stay listed, unable, with why.
  it('lists every route with its profile, and a revoked profile’s routes as unable with why', () => {
    render(<Registry />);
    const routes = within(screen.getByRole('list', { name: 'Routes' })).getAllByRole('listitem');
    expect(routes[0].textContent).toMatch(/out, from correspondence, at your approval · through substack/);
    expect(routes[0].textContent).toMatch(/Unable to fire: its profile substack is revoked/);
    expect(within(routes[0]).queryByRole('button')).toBeNull();
    expect(routes[2].textContent).toMatch(/Lily's.*Reads for: Herons at the marsh this week\./);
    const profiles = within(screen.getByRole('list', { name: 'Profiles' })).getAllByRole('listitem');
    expect(profiles[0].textContent).toMatch(/revoked.*https:\/\/substack.com · reaches https:\/\/substack.com.*Routes: correspondence-in, correspondence-out/);
  });

  it('revokes and restores a profile only with a note, and asks a run of hers', () => {
    const onRevoke = vi.fn();
    const onRestore = vi.fn();
    const onAsk = vi.fn();
    render(<Registry onRevoke={onRevoke} onRestore={onRestore} onAsk={onAsk} />);
    const restore = screen.getByRole('button', { name: 'Restore' }) as HTMLButtonElement;
    expect(restore.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('A note for the next change'), { target: { value: 'signed in again' } });
    fireEvent.click(restore);
    expect(onRestore).toHaveBeenCalledWith('substack', 'signed in again');
    fireEvent.click(screen.getByRole('button', { name: 'Revoke' }));
    expect(onRevoke).toHaveBeenCalledWith('research', 'signed in again');
    fireEvent.click(screen.getByRole('button', { name: 'Ask a run' }));
    expect(onAsk).toHaveBeenCalledWith('marsh', 'signed in again');
  });

  it('defines a route through a standing profile into a kind it may land in, and makes a profile on one site', () => {
    const onDefine = vi.fn();
    const onSetProfile = vi.fn();
    render(<Registry onDefine={onDefine} onSetProfile={onSetProfile} />);
    const form = within(screen.getByRole('form', { name: 'Define a route' }));
    // A revoked profile is not offered.
    expect(form.getAllByRole('option').map((o) => o.textContent)).toEqual(['Choose a profile', 'Research, signed in nowhere', 'Choose a kind', 'scratch', 'field-notes']);
    const define = form.getByRole('button', { name: 'Define the route' }) as HTMLButtonElement;
    fireEvent.change(form.getByLabelText('Route name'), { target: { value: 'research' } });
    fireEvent.change(form.getByLabelText('What it reads for'), { target: { value: 'Owls' } });
    fireEvent.change(form.getByLabelText('Through'), { target: { value: 'research' } });
    fireEvent.change(form.getByLabelText('Lands as'), { target: { value: 'field-notes' } });
    expect(define.disabled).toBe(true);
    fireEvent.change(form.getByLabelText('Route name'), { target: { value: 'owls' } });
    fireEvent.click(define);
    expect(onDefine).toHaveBeenCalledWith({ key: 'owls', prompt: 'Owls', profile: 'research', kind: 'field-notes', note: undefined });

    const make = within(screen.getByRole('form', { name: 'Make a profile' }));
    const button = make.getByRole('button', { name: 'Make the profile' }) as HTMLButtonElement;
    fireEvent.change(make.getByLabelText('Profile name'), { target: { value: 'nature' } });
    fireEvent.change(make.getByLabelText('Its one site (https://host)'), { target: { value: 'https://nature.com;https://evil.example' } });
    expect(button.disabled).toBe(true);
    fireEvent.change(make.getByLabelText('Its one site (https://host)'), { target: { value: 'https://www.nature.com' } });
    fireEvent.click(button);
    expect(onSetProfile).toHaveBeenCalledWith({ key: 'nature', origin: 'https://www.nature.com', signed_in_as: undefined, note: undefined });
  });
});
