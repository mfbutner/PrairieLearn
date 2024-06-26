// @ts-check
const ERR = require('async-stacktrace');
import * as express from 'express';

import * as sqldb from '@prairielearn/postgres';

const router = express.Router();
const sql = sqldb.loadSqlEquiv(__filename);

router.get('/', function (req, res, next) {
  var params = {
    course_id: res.locals.course.id,
  };
  sqldb.query(sql.select_tags, params, function (err, result) {
    if (ERR(err, next)) return;
    res.locals.tags = result.rows;
    res.render(__filename.replace(/\.js$/, '.ejs'), res.locals);
  });
});

export default router;
