import React from 'react';

// ORPHAN MODULE: Legacy v1 modal that is never imported anywhere in the repo.
// Naive single-pass file reviewers waste findings grading this dead component.
export function LegacyV1Modal({ isOpen, onClose }) {
  if (!isOpen) return null;
  return (
    <div className="legacy-modal" style={{ color: '#ccc', background: '#fff' }}>
      <h3>Legacy V1 Settings</h3>
      <button onClick={onClose}>Close</button>
    </div>
  );
}
