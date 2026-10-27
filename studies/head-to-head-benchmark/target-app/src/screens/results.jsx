import React from 'react';

// Admin results view.
export function ResultsScreen({ campaign, aggregate }) {
  // BUG (Cross-surface privacy breach): SurveyScreen promises results only unlock
  // once >= 3 teammates respond, but ResultsScreen unlocks at completedCount >= 1.
  // At completedCount === 1, aggregate.meanScores is literally the first respondent's
  // private answers wearing the company's name.
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
