import * as express from 'express';
import * as handlebars from 'express-handlebars';
import * as request from 'request-promise';

const app = express();

app.engine('.hbs', handlebars({extname: '.hbs'}));
app.set('view engine', '.hbs');

async function getAllWeather(): Promise<any> {
  return request.get(process.env.API_URL + "/weather", {json: true});
}

app.get('/', async (req, res) => {
  res.render('index', {weathers: (await getAllWeather()) || null, layout: false});
});

app.listen(80);
