#include <ike/types.h>
#include <ike/gc.h>

typedef struct ike_body_1_input ike_body_1_input;

struct ike_body_1_input {
  ike_string input_0;
};

typedef struct ike_body_0_input ike_body_0_input;

struct ike_body_0_input {

};

void ike_body_1(ike_body_1_input *input, ike_unit *output);

static const ike_function_vtable ike_body_1_vtable = {
  .call = (typeof(ike_body_1_vtable.call))ike_body_1,
};

void ike_body_0(ike_body_0_input *input, ike_unit *output);

static const ike_function_vtable ike_body_0_vtable = {
  .call = (typeof(ike_body_0_vtable.call))ike_body_0,
};

void ike_body_1(ike_body_1_input *input, ike_unit *output) { printf("%s", input->input_0->contents); }

void ike_body_0(ike_body_0_input *input, ike_unit *output) {


  ike_unit temp_0;
  ike_string temp_1;
  ike_function temp_2;
  ike_body_1(NULL, &temp_2);
  temp_1 = ike_string_new("hello");
  ike_call(temp_2, &temp_1, (sizeof temp_1), &temp_0);
  *output = temp_0;
}