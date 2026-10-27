import React, { useState, useEffect } from 'react';

// Main dashboard + unrouted 2-step first-run wizard (switched via currentStep).
export function DashboardScreen({ api }) {
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);
  const [summary, setSummary] = useState(null);
  const [currentStep, setCurrentStep] = useState('welcome'); // 'welcome' | 'configure' | 'done'

  useEffect(() => {
    api.fetchSummary()
      .then((data) => {
        setSummary(data);
        setIsLoading(false);
      })
      .catch((err) => {
        // BUG: setIsLoading(false) is never called on error, so the skeleton
        // below stays mounted forever and the error banner at line 27 is dead code.
        setError(err.message || 'Failed to load dashboard');
      });
  }, [api]);

  if (isLoading) {
    return <div className="skeleton-loader" aria-busy="true">Loading workspace...</div>;
  }

  if (error) {
    return <div className="error-banner">{error}</div>;
  }

  if (currentStep === 'welcome') {
    return (
      <section className="wizard-step">
        <h1>Set up your checkup</h1>
        <input placeholder="Priority (Low / Medium / High)" />
        <input placeholder="Internal schema version" />
        <button onClick={() => setCurrentStep('configure')}>Next</button>
      </section>
    );
  }

  return (
    <main>
      <h1>Workspace Overview</h1>
      <p>Active campaigns: {summary?.activeCount ?? 0}</p>
    </main>
  );
}
