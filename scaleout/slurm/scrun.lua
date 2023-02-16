function slurm_scrun_stage_in(id, bundle, spool_dir, config_file, job_id, user_id, group_id, job_env)
        slurm.log_debug(string.format("stage_in(%s, %s, %s, %s, %d, %d, %d)",
                       id, bundle, spool_dir, config_file, job_id, user_id, group_id))
        return slurm.SUCCESS
end

function slurm_scrun_stage_out(id, bundle, orig_bundle, root_path, orig_root_path, spool_dir, config_file, jobid, user_id, group_id)
        slurm.log_debug(string.format("stage_out(%s, %s, %s, %s, %s, %s, %s, %d, %d, %d)",
                       id, bundle, orig_bundle, root_path, orig_root_path, spool_dir, config_file, jobid, user_id, group_id))
        return slurm.SUCCESS
end

slurm.log_info("initialized scrun.lua")

return slurm.SUCCESS
