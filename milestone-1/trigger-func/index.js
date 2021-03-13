const bodyParser = require('body-parser');
const express = require('express');
const _ = require('lodash');
const uuid = require('uuid').v4;

const config = {
  // Knative defaults to port 8080.
  port: 8080,
};

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

  res.status(201).send();
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
