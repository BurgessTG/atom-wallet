import '../../extension/src/engine-worker.js';
import * as progress from './progress.js';
import { liveSubmission } from './submission.js';

self.mdwaProgress = progress;
self.mdwaSubmissionService = liveSubmission;
