const { ServiceBusClient } = require("@azure/service-bus");

module.exports = (context, req) => {
  const sbClient = ServiceBusClient.createFromConnectionString(process.env.AZURE_SERVICEBUS_CONNECTION_STRING);
  const queueClient = sbClient.createQueueClient(process.env.AZURE_SERVICEBUS_QUEUE_NAME);
  const sender = queueClient.createSender();

  try {
    req.body.datetime = new Date().toISOString();
    const message = {
      body: req.body
    };
    sender.send(message).then(() => queueClient.close().then(() => context.done()));
  } finally {
    sbClient.close().then();
  }
}
;
