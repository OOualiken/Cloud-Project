import express from 'express';
import {createConnection, DeepPartial, Repository} from 'typeorm';
import {Weather} from './entity/weather';
import {ReceiveMode, ServiceBusClient} from '@azure/service-bus';

const app = express();

createConnection({
  type: "mysql",
  host: process.env.MYSQL_HOST,
  port: parseInt(process.env.MYSQL_PORT),
  username: process.env.MYSQL_USERNAME,
  password: process.env.MYSQL_PASSWORD,
  database: process.env.MYSQL_DATABASE,
  entities: [
    Weather
  ],
  synchronize: true,
  logging: true
}).then(connection => {
  const weatherRepository: Repository<Weather> = connection.getRepository(Weather);

  const sbClient = ServiceBusClient.createFromConnectionString(process.env.AZURE_SERVICEBUS_CONNECTION_STRING);
  const queueClient = sbClient.createQueueClient(process.env.QUEUE_NAME);
  const receiver = queueClient.createReceiver(ReceiveMode.receiveAndDelete);

  setInterval(async () => {
      const messages = await receiver.receiveMessages(1, 1);
      console.log("Received message");
      console.log(messages);

      if (messages.length > 0) {
        const newWeather: Weather = await weatherRepository.create(messages[0].body as DeepPartial<Weather>);
        await weatherRepository.save(newWeather);
      }
  }, 2000);

  app.get('/', (req, res) => {
    res.send('Hello World');
  });

  app.get('/weather', async (req, res) => {
    res.setHeader("Content-type", "application/json");
    res.send(JSON.stringify(await weatherRepository.find()));
  });

  app.post('/weather', async (req, res) => {
    const newWeather: Weather = await weatherRepository.create(JSON.parse(req.body) as DeepPartial<Weather>);
    await weatherRepository.save(newWeather);
    res.setHeader("Content-type", "application/json");
    res.send(JSON.stringify({
      result: {
        message: "saved",
        date: new Date().toISOString()
      }
    }));
  });

  app.listen(8080);
}).catch(error => console.log(error));
