import { initialize } from './helpers/make-suite';

before(async () => {
    console.log('--> Deploying test environment...\n');
    await initialize();
    console.log('\n--> Setup finished...\n');
});