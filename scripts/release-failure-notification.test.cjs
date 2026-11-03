const assert = require('node:assert/strict');
const { test } = require('node:test');
const notification = require('./release-failure-notification.cjs');

const runUrl = 'https://github.com/PostHog/posthog-ios/actions/runs/41112249150';
const channel = 'release-approvals';
const releaseJob = 'Tag and create GitHub release';
const notifyJob = 'Notify Slack - Released';

function job(name, conclusion, steps = []) {
    return { name, conclusion, steps, html_url: `${runUrl}/job/124277053824` };
}

async function inspect(jobs, conclusion = 'success', attempt = 1) {
    const listJobsForWorkflowRunAttempt = () => {};
    return notification({
        channel,
        context: {
            repo: { owner: 'PostHog', repo: 'posthog-ios' },
            payload: { workflow_run: { id: 41112249150, run_attempt: attempt, conclusion, html_url: runUrl } },
        },
        github: {
            rest: { actions: { listJobsForWorkflowRunAttempt } },
            paginate: async (method, params) => {
                assert.equal(method, listJobsForWorkflowRunAttempt);
                assert.deepEqual(params, {
                    owner: 'PostHog', repo: 'posthog-ios', run_id: 41112249150,
                    attempt_number: attempt, per_page: 100,
                });
                return jobs;
            },
        },
    });
}

test('run 41112249150: runner brownout cancels CocoaPods before any steps start', async () => {
    const payload = await inspect([
        job('Check for changesets', 'success'),
        job('Notify Slack - Approval Needed / notify', 'success'),
        job('Bump version and commit to main', 'success'),
        job(releaseJob, 'success'),
        job('Notify Slack - Rejected', 'skipped'),
        job('Publish to CocoaPods', 'cancelled'),
        job(notifyJob, 'skipped'),
    ], 'cancelled');

    assert.equal(payload.channel, channel);
    assert.match(payload.text, /❌ Release process failed or was cancelled/);
    assert.match(payload.text, /Publish to CocoaPods>: cancelled/);
    assert.match(payload.text, /released Slack notification did not run/);
    assert.match(payload.text, /GitHub\/SPM release exists/);
    assert.ok(payload.text.includes(`<${runUrl}|View release logs>`));
    assert.equal(payload.thread_ts, undefined);
});

for (const name of ['Check for changesets', 'Bump version and commit to main', releaseJob, 'Publish to CocoaPods', notifyJob]) {
    for (const conclusion of ['failure', 'cancelled', 'timed_out', 'startup_failure']) {
        test(`${name}: reports ${conclusion} even without job steps or a Slack thread`, async () => {
            const payload = await inspect([{ ...job(name, conclusion), steps: undefined }], conclusion);
            assert.ok(payload.text.includes(`${name}>: ${conclusion}`));
        });
    }
}

test('best-effort CocoaPods failure is reported even when the workflow and job succeed', async () => {
    const payload = await inspect([
        job(releaseJob, 'success'),
        job('Publish to CocoaPods', 'success', [{ name: 'Publish to CocoaPods', conclusion: 'failure' }]),
        job(notifyJob, 'success'),
    ]);
    assert.match(payload.text, /Publish to CocoaPods>:? \/ Publish to CocoaPods: failure/);
    assert.match(payload.text, /CocoaPods publishing is best-effort/);
});

test('continue-on-error Slack failure is reported despite a successful job and run', async () => {
    const payload = await inspect([
        job(releaseJob, 'success'),
        job(notifyJob, 'success', [{ name: 'Notify Slack - Released', conclusion: 'failure' }]),
    ]);
    assert.match(payload.text, /Notify Slack - Released> \/ Notify Slack - Released: failure/);
});

test('approval notification failure does not depend on a thread timestamp', async () => {
    const payload = await inspect([
        job('Notify Slack - Approval Needed / notify', 'success', [
            { name: 'Send Slack notification', conclusion: 'failure' },
        ]),
    ]);
    assert.match(payload.text, /Send Slack notification: failure/);
    assert.equal(payload.channel, channel);
});

test('whole-run cancellation still alerts if all existing jobs succeeded or skipped', async () => {
    const payload = await inspect([
        job('Check for changesets', 'success'),
        job('Bump version and commit to main', 'skipped'),
    ], 'cancelled');
    assert.match(payload.text, /run: cancelled/);
});

test('a missing released notification after GitHub release creation alerts', async () => {
    const payload = await inspect([job(releaseJob, 'success')]);
    assert.match(payload.text, /released Slack notification did not run/);
});

test('successful release does not send a failure message', async () => {
    assert.equal(await inspect([
        job(releaseJob, 'success'),
        job('Publish to CocoaPods', 'success'),
        job(notifyJob, 'success'),
        job('Notify Slack - Rejected', 'skipped'),
    ]), null);
});

test('no changesets is a successful no-op, not a release failure', async () => {
    assert.equal(await inspect([
        job('Check for changesets', 'success'),
        job('Bump version and commit to main', 'skipped'),
        job(releaseJob, 'skipped'),
        job('Publish to CocoaPods', 'skipped'),
        job(notifyJob, 'skipped'),
    ]), null);
});

test('reruns only inspect jobs for the completed attempt, not old failures', async () => {
    assert.equal(await inspect([job(releaseJob, 'success'), job(notifyJob, 'success')], 'success', 2), null);
});

test('job API errors fail the observer rather than silently suppressing the alert', async () => {
    await assert.rejects(notification({
        channel,
        context: { repo: {}, payload: { workflow_run: { id: 1, run_attempt: 1 } } },
        github: {
            rest: { actions: {} },
            paginate: async () => { throw new Error('GitHub API unavailable'); },
        },
    }), /GitHub API unavailable/);
});
