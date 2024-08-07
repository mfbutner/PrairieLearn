import { Router } from 'express';
import asyncHandler from 'express-async-handler';

import { loadSqlEquiv, queryOneRowAsync } from '@prairielearn/postgres';

import { redirectToTermsPageIfNeeded } from '../../ee/lib/terms.js';
import { config } from '../../lib/config.js';
import { isEnterprise } from '../../lib/license.js';

const sql = loadSqlEquiv(import.meta.url);
const router = Router();

router.get(
  '/',
  asyncHandler(async (req, res) => {
    res.locals.navPage = 'home';

    // Potentially prompt the user to accept the terms before proceeding.
    if (isEnterprise()) {
      await redirectToTermsPageIfNeeded(res, res.locals.authn_user, req.ip, req.originalUrl);
    }

    const result = await queryOneRowAsync(sql.select_home, {
      user_id: res.locals.authn_user.user_id,
      is_administrator: res.locals.is_administrator,
      req_date: res.locals.req_date,
      // This is a somewhat ugly escape hatch specifically for load testing. In
      // general, we don't want to clutter the home page with example course
      // enrollments, but for load testing we want to enroll a large number of
      // users in the example course and then have them find the example course
      // on the home page. So, you'd make a request like this:
      // `/pl?include_example_course_enrollments=true`
      include_example_course_enrollments: req.query.include_example_course_enrollments === 'true',
    });

    res.locals.instructor_courses = result.rows[0].instructor_courses;
    res.locals.student_courses = result.rows[0].student_courses;

    // Example courses are only shown to users who are either instructors of
    // at least one other course, or who are admins. They're also shown
    // unconditionally in dev mode.
    if (res.locals.instructor_courses.length > 0 || res.locals.is_administrator || config.devMode) {
      res.locals.instructor_courses = res.locals.instructor_courses.concat(
        result.rows[0].example_courses,
      );
    }

    res.render(import.meta.filename.replace(/\.[jt]s$/, '.ejs'), res.locals);
  }),
);

export default router;
