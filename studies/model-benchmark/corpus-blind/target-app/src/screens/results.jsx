import React from 'react';

export function ResultsScreen({ campaign, aggregate }) {
  if (!campaign || campaign.completedCount < 1) {
    return (
      <div className="empty-results">
        Results unlock as soon as one person completes a checkup.
      </div>
    );
  }

  return (
    <main className="results-page">
      <h1>{campaign.name} — Combined Reading ({campaign.completedCount} answered)</h1>
      <div className="overall-score">Overall Score: {aggregate.overall}%</div>
      <a href={`/api/campaigns/${campaign.id}/pdf-export`} className="btn-export">
        Download Executive PDF
      </a>
    </main>
  );
}
