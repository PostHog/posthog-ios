const unsuccessful = new Set(['failure', 'cancelled', 'timed_out', 'action_required', 'startup_failure', 'stale']);

module.exports = async function releaseFailureNotification({ github, context, channel }) {
    const run = context.payload.workflow_run;
    const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRunAttempt, {
        ...context.repo,
        run_id: run.id,
        attempt_number: run.run_attempt,
        per_page: 100,
    });

    const problems = jobs.flatMap(job => {
        const failedSteps = (job.steps || []).filter(step => unsuccessful.has(step.conclusion));
        if (unsuccessful.has(job.conclusion)) {
            return [`• <${job.html_url}|${job.name}>: ${job.conclusion}`];
        }
        // Best-effort jobs and Slack steps can fail without failing the run.
        return failedSteps.map(step => `• <${job.html_url}|${job.name}> / ${step.name}: ${step.conclusion}`);
    });

    const releaseCreated = jobs.some(job => job.name === 'Tag and create GitHub release' && job.conclusion === 'success');
    const releasedNotification = jobs.find(job => job.name === 'Notify Slack - Released');
    if (releaseCreated && (!releasedNotification || releasedNotification.conclusion === 'skipped')) {
        problems.push('• The released Slack notification did not run.');
    }

    if (problems.length === 0 && run.conclusion === 'success') {
        return null;
    }

    return {
        channel,
        text: [
            `❌ Release process failed or was cancelled for \`${context.repo.owner}/${context.repo.repo}\` (attempt ${run.run_attempt}).`,
            ...problems,
            ...(releaseCreated ? ['The GitHub/SPM release exists. CocoaPods publishing is best-effort; check its status separately.'] : []),
            `<${run.html_url}|View release logs> (run: ${run.conclusion})`,
        ].join('\n'),
        unfurl_links: false,
        unfurl_media: false,
    };
};
