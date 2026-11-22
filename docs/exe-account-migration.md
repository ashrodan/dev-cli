# Move VMs from one exe.dev account to another

exe.dev has no command that moves a VM between two separate accounts. It can
move a VM between two members of one team (`team transfer`). To move VMs from
a personal account into a team account, make the personal account a team
member first, then transfer each VM.

The VM keeps its disk, its name and its `<name>.exe.xyz` host. Integrations do
not move: they belong to the account that made them.

## Before you start

1. Audit both accounts, and keep the output:

   ```sh
   dev -H <personal-profile> fleet audit
   dev -H <team-profile>     fleet audit
   ssh <personal-profile> integrations list > personal-integrations.txt
   ```

2. Check the team's capacity: `ssh <team-profile> billing plan` and
   `ssh <team-profile> team usage`. Moved VMs share the target member's
   capacity, and a VM that does not fit stops at transfer time.
3. For each integration attached to a VM that moves, write down how to make it
   again on the team: its type, its target, and what attaches it (`vm:` or
   `tag:`). Peerings (`http-proxy`) have a hostname of the form
   `<name>.int.exe.xyz`. Make each one again with the **same name**, so that
   the URLs in the boxes' environment files stay correct.
4. A Workload Identity Federation integration (`wif`) gets a new issuer and
   subject on the team. Update the trust policy in the cloud provider (GCP pool
   provider, AWS IAM role) before you remove the old integration.

## Move

Do the steps in this order. Do one VM, check it, then do the rest.

1. Invite the personal account. The invite expires after 24 hours.

   ```sh
   ssh <team-profile> team add <personal-email>
   ```

2. Accept the invite at <https://exe.dev/user/teams> while signed in as the
   personal account. The personal VMs are now team VMs.
3. Transfer each VM to the team member who will own it:

   ```sh
   ssh <team-profile> team transfer <vm> <owner-email>
   ```

4. Make the integrations again on the team and attach them (step 3 of
   "Before you start").
5. Change `~/.ssh/config` so that the moved hosts use the team key. exe.dev
   picks the account from the key, so a host that still pins the personal key
   reaches the wrong account and fails with "VM not found". Run `fleet-hosts`
   again for each account.
6. Check each moved VM:

   ```sh
   dev -H <team-profile> fleet audit
   ```

   Then check each service end to end, not only that `systemctl` reports it as
   active. For example, for a peering, send a request through the
   `.int.exe.xyz` host and get the expected answer.

## After the move

1. Remove the integrations from the personal account only after the team's
   copies work.
2. Remove the personal account from the team. If it still owns VMs, the
   command refuses and lists them.

   ```sh
   ssh <team-profile> team remove <personal-email>
   ```

3. Cancel the personal plan, if you no longer use it.
