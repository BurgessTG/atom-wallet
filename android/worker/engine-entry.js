import '../../extension/src/engine-worker.js';
import * as contracts from './preview-contract.js';

import * as progress from './progress.js';
import { liveSubmission } from './submission.js';

self.mdwaPreviewContracts = contracts;
self.mdwaProgress = progress;
self.mdwaSubmissionService = liveSubmission;
