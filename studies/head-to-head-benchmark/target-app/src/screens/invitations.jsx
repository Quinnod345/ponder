import React from 'react';

// Admin invitations roster.
export function InvitationsScreen({ participants }) {
  return (
    <main className="invitations-page">
      <h1>Campaign Invitations</h1>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Status</th>
            <th>Individual Score</th>
            <th>Magic Link</th>
          </tr>
        </thead>
        <tbody>
          {participants.map((p) => (
            // BUG: Renders each named person's individual score and exposes their
            // raw surveyHash bearer credential to the admin table DOM.
            <tr key={p.id}>
              <td>{p.name}</td>
              <td>{p.completedAt ? 'Completed' : 'Pending'}</td>
              <td>{p.completedAt ? `${p.individualScore}%` : '—'}</td>
              <td><code>/survey/{p.surveyHash}</code></td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
