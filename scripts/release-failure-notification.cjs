const unsuccessful = new Set(['failure', 'cancelled', 'timed_out', 'action_required', 'startup_failure', 'stale']);

module.exports = async function releaseFailureNotification({ github, context, channel }) {
    const run = context.payload.workflow_run;
    let jobs;
    try {
        jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRunAttempt, {
            ...context.repo,
            run_id: run.id,
            attempt_number: run.run_attempt,
            per_page: 100,
        });
    } catch {
        return {
            channel,
            text: [
                `⚠️ Could not inspect release jobs for \`${context.repo.owner}/${context.repo.repo}\` (attempt ${run.run_attempt}).`,
                'Please check this release manually; individual job results are unavailable.',
                `<${run.html_url}|View release logs> (run: ${run.conclusion})`,
            ].join('\n'),
            unfurl_links: false,
            unfurl_media: false,
        };
    }

    const problems = jobs
        .filter(job => unsuccessful.has(job.conclusion))
        .map(job => `• <${job.html_url}|${job.name}>: ${job.conclusion}`);

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
