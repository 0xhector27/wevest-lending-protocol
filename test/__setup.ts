import { initialize } from './helpers/make-suite';

before(async () => {
    console.log('-> Deploying test environment...');
    await initialize();
    console.log('-> Setup finished...');
});