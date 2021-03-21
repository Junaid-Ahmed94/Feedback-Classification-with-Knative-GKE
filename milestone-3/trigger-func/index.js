const bodyParser = require('body-parser');
const express = require('express');
const Firestore = require('@google-cloud/firestore');
const { PubSub } = require('@google-cloud/pubsub');
const _ = require('lodash');
const uuid = require('uuid').v4;

const config = {
  // Knative defaults to port 8080.
  port: 8080,
};

// Deploying to a Knative service using a Kubernetes service account associated
// with a Google SA (using Workload Identity), so no need to create a service
// account key and provide its path in the constructor options for the GCP
// clients, and no need to specify project ID.
const feedbackRef = new Firestore().collection('feedback');
const pubsubClient = new PubSub();

const app = express();

// Allows receiving JSON body requests for adding new feedback
app.use(bodyParser.json());

app.post('/', async (req, res) => {
  const input = req.body;

  // Validation
  if (_.isNil(input.feedback)) {
    const msg = 'Missing input param "feedback".';
    console.log(msg);
    res.status(400).send(msg);
    return;
  }

  const newFeedbackId = uuid();

  // Save validated feedback
  try {
    const newFeedback = input;

    newFeedback.createdAt = new Date().toISOString();
    newFeedback.classified = false;

    await feedbackRef.doc(newFeedbackId).set(newFeedback);
    console.log(`New feedback saved in Firestore (new feedback ID = ${newFeedbackId}).`);

    // Notify via Pub/Sub that feedback was created.
    const msg = JSON.stringify({
      newFeedbackId,
    });
    await pubsubClient.topic('feedback-created').publish(Buffer.from(msg));
    console.log(`Message published to Pub/Sub (new feedback ID = ${newFeedbackId}).`);

    res.status(201).send();
    return;
  } catch (e) {
    console.log(`Error saving feedback and publishing Pub/Sub message (new feedback ID = ${newFeedbackId}):`, e);

    res.status(500).send();
    return;
  }
});

const server = app.listen(config.port, () => {
  console.log(`trigger-func app listening at http://localhost:${config.port}`);
});

// Capture SIGINT and SIGTERM and perform shutdown. Helps make sure the pod
// gets terminated within a reasonable amount of time.
process.on('SIGINT', () => {
  console.log(`Received SIGINT at ${new Date()}.`);
  shutdown();
});
process.on('SIGTERM', () => {
  console.log(`Received SIGTERM at ${new Date()}.`);
  shutdown();
});

function shutdown() {
  console.log('Beginning graceful shutdown of Express app server.');
  server.close(function () {
    console.log('Express app server closed.');
  });
  process.exit(0);
}
