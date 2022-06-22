CREATE FUNCTION
    instance_questions_points_homework(
        IN instance_question_id bigint,
        IN submission_score DOUBLE PRECISION,
        OUT open BOOLEAN,
        OUT status enum_instance_question_status,
        OUT auto_points DOUBLE PRECISION,
        OUT auto_score_perc DOUBLE PRECISION,
        OUT highest_submission_score DOUBLE PRECISION,
        OUT current_value DOUBLE PRECISION,
        OUT points_list DOUBLE PRECISION[],
        OUT variants_points_list DOUBLE PRECISION[],
        OUT max_auto_points DOUBLE PRECISION
    )
AS $$
DECLARE
    iq instance_questions%ROWTYPE;
    assessment_question assessment_questions%ROWTYPE;
    correct boolean;
    constant_question_value boolean;
    length integer;
    var_points_old double precision;
    var_points_new double precision;

BEGIN
    SELECT * INTO iq FROM instance_questions WHERE id = instance_question_id;
    SELECT aq.*, aqsmp.* INTO assessment_question
    FROM
        assessment_questions aq
        JOIN questions AS q ON (q.id = aq.question_id)
        JOIN assessment_questions_select_manual_points(aq, q) as aqsmp ON (TRUE)
    WHERE
        aq.id = iq.assessment_question_id;

    max_auto_points := assessment_question.max_auto_points;
    highest_submission_score := greatest(submission_score, coalesce(iq.highest_submission_score, 0));

    open := TRUE;
    points_list := NULL;

    -- if the submission was not correct, then immediately reset current_value
    correct := (submission_score >= 1.0);
    IF NOT correct THEN
        current_value := assessment_question.init_points;
    ELSE
        current_value := iq.current_value;
    END IF;

    -- modify variants_points_list
    variants_points_list := iq.variants_points_list;
    length := cardinality(variants_points_list);
    var_points_old := coalesce(variants_points_list[length], 0);
    var_points_new := submission_score*current_value;
    IF (length > 0) AND (var_points_old < assessment_question.init_points) THEN
        IF (var_points_old < var_points_new) THEN
            variants_points_list[length] = var_points_new;
        END IF;
    ELSE
        variants_points_list := array_append(variants_points_list, var_points_new);
    END IF;

    -- get property that says if we should change current_value or not
    SELECT a.constant_question_value INTO constant_question_value FROM assessments AS a WHERE a.id = assessment_question.assessment_id;

    -- if the submission was correct, increment current_value
    IF correct AND NOT constant_question_value THEN
        current_value := least(iq.current_value + assessment_question.init_points, assessment_question.max_auto_points);
    END IF;

    -- points is the sum of all elements in variants_points_list (which now must be non-empty)
    length := cardinality(variants_points_list);
    auto_points := 0;
    FOR i in 1..length LOOP
        auto_points := auto_points + variants_points_list[i];
    END LOOP;
    auto_points := least(auto_points, assessment_question.max_auto_points);

    -- score_perc
    auto_score_perc := auto_points / (CASE WHEN assessment_question.max_auto_points > 0 THEN assessment_question.max_auto_points ELSE 1 END) * 100;

    -- status
    IF correct THEN
        status := 'correct';
    ELSE
        -- use current status unless it's 'unanswered'
        status := iq.status;
        IF iq.status = 'unanswered' THEN
            status := 'incorrect';
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;
