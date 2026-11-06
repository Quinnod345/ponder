import React from 'react';

export function LegacyV1Modal({ isOpen, onClose }) {
  if (!isOpen) return null;
  return (
    <div className="legacy-modal" style={{ color: '#ccc', background: '#fff' }}>
      <h3>Legacy V1 Settings</h3>
      <button onClick={onClose}>Close</button>
    </div>
  );
}
